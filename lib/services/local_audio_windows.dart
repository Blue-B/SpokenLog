import 'dart:typed_data';

/// Half-open sample range `[start, end)` decoded in one engine call.
typedef AudioWindow = ({int start, int end});

/// Splits [samples] into windows no longer than [maxSeconds].
///
/// Local engines cannot take arbitrarily long audio: sherpa-onnx's Whisper
/// keeps only the first 30 seconds and silently drops the rest. Each cut is
/// placed at the quietest 50 ms inside the last [searchSeconds] of a window so
/// words are rarely split in half. Recordings that already fit yield a single
/// window covering everything.
List<AudioWindow> planAudioWindows(
  Float32List samples,
  int sampleRate, {
  required double maxSeconds,
  double searchSeconds = 4,
}) {
  if (samples.isEmpty || sampleRate <= 0) return const [];

  final maxSamples = (maxSeconds * sampleRate).floor();
  if (maxSamples <= 0 || samples.length <= maxSamples) {
    return [(start: 0, end: samples.length)];
  }

  final searchSamples =
      (searchSeconds * sampleRate).floor().clamp(0, maxSamples ~/ 2);
  final frame = sampleRate ~/ 20 > 0 ? sampleRate ~/ 20 : 1;
  final windows = <AudioWindow>[];
  var start = 0;

  while (samples.length - start > maxSamples) {
    final hardEnd = start + maxSamples;
    var cut = hardEnd;
    var quietest = double.infinity;
    for (var f = hardEnd - searchSamples; f + frame <= hardEnd; f += frame) {
      var energy = 0.0;
      for (var i = f; i < f + frame; i++) {
        energy += samples[i].abs();
      }
      // `<=` prefers the later frame when equally quiet, keeping windows full.
      if (energy <= quietest) {
        quietest = energy;
        cut = f + frame ~/ 2;
      }
    }
    windows.add((start: start, end: cut));
    start = cut;
  }
  windows.add((start: start, end: samples.length));
  return windows;
}

/// Splits [samples] at natural pauses into speech-only pieces for engines that
/// return no per-word times.
///
/// Whisper as shipped for sherpa-onnx has no timestamp output, so each piece's
/// own start and end become the subtitle times. Pieces are cut where the audio
/// stays quiet for [pauseSeconds], merged until they reach [minSeconds], and
/// never exceed [maxSeconds] (an over-long stretch is cut at its quietest
/// point). Leading and trailing silence is trimmed and pure silence is dropped.
/// If no speech is detected at all, this falls back to [planAudioWindows] so a
/// very quiet recording is still transcribed.
List<AudioWindow> planSpeechWindows(
  Float32List samples,
  int sampleRate, {
  double minSeconds = 3,
  double maxSeconds = 12,
  double pauseSeconds = 0.4,
}) {
  if (samples.isEmpty || sampleRate <= 0) return const [];

  final frame = sampleRate ~/ 50 > 0 ? sampleRate ~/ 50 : 1;
  final frames = samples.length ~/ frame;
  final rms = List<double>.filled(frames, 0);
  for (var f = 0; f < frames; f++) {
    var sum = 0.0;
    for (var i = f * frame; i < (f + 1) * frame; i++) {
      sum += samples[i] * samples[i];
    }
    rms[f] = sum / frame; // mean square; compared against a squared threshold
  }

  final sorted = [...rms]..sort();
  double level(double q) =>
      sorted.isEmpty ? 0 : sorted[(q * (sorted.length - 1)).round()];
  // Thresholds are on mean-square values, so "4x the noise floor" in amplitude
  // is 16x here. Never below a faint hiss, never above 30% of loud speech.
  var threshold = level(0.1) * 16;
  final ceiling = level(0.9) * 0.09;
  if (threshold > ceiling) threshold = ceiling;
  if (threshold < 0.003 * 0.003) threshold = 0.003 * 0.003;

  final voiced = [for (final e in rms) e >= threshold];
  if (!voiced.contains(true)) {
    return planAudioWindows(samples, sampleRate, maxSeconds: 28);
  }

  final pauseFrames = (pauseSeconds * 50).round();
  // Speech runs, bridging quiet gaps shorter than a pause.
  final runs = <({int start, int end})>[];
  var runStart = -1;
  var lastVoiced = -1;
  for (var f = 0; f < frames; f++) {
    if (!voiced[f]) continue;
    if (runStart < 0) {
      runStart = f;
    } else if (f - lastVoiced > pauseFrames) {
      runs.add((start: runStart, end: lastVoiced + 1));
      runStart = f;
    }
    lastVoiced = f;
  }
  if (runStart >= 0) runs.add((start: runStart, end: lastVoiced + 1));

  final minFrames = (minSeconds * 50).round();
  final maxFrames = (maxSeconds * 50).round();
  final grouped = <({int start, int end})>[];
  var current = runs.first;
  for (final run in runs.skip(1)) {
    if (current.end - current.start < minFrames &&
        run.end - current.start <= maxFrames) {
      current = (start: current.start, end: run.end);
    } else {
      grouped.add(current);
      current = run;
    }
  }
  grouped.add(current);

  final pad = (0.1 * sampleRate).round();
  final windows = <AudioWindow>[];
  for (var g = 0; g < grouped.length; g++) {
    final lower = g == 0 ? 0 : windows.last.end;
    final upper = g + 1 < grouped.length
        ? grouped[g + 1].start * frame
        : samples.length;
    final start = (grouped[g].start * frame - pad).clamp(lower, samples.length);
    final end = (grouped[g].end * frame + pad).clamp(start, upper);
    if (end - start <= maxFrames * frame) {
      windows.add((start: start, end: end));
      continue;
    }
    // One unbroken stretch longer than the limit: cut it at quiet points.
    final part = samples.sublist(start, end);
    for (final w in planAudioWindows(part, sampleRate, maxSeconds: maxSeconds)) {
      windows.add((start: start + w.start, end: start + w.end));
    }
  }
  return windows;
}

// CJK punctuation, kana, ideographs, compatibility ideographs, full-width forms.
final RegExp _unspacedScript = RegExp(
  r'[\u3000-\u303f\u3040-\u30ff\u3400-\u9fff\uf900-\ufaff\uff00-\uffef]',
);

/// Joins per-window transcripts back into one text.
///
/// Windows are pieces of the same passage, so they are joined with a space,
/// or with nothing when either side is Chinese/Japanese text (no word spaces).
String joinTranscriptPieces(Iterable<String> pieces) {
  final buffer = StringBuffer();
  var previousLast = '';
  for (final raw in pieces) {
    final piece = raw.trim();
    if (piece.isEmpty) continue;
    if (previousLast.isNotEmpty &&
        !_unspacedScript.hasMatch(previousLast) &&
        !_unspacedScript.hasMatch(piece[0])) {
      buffer.write(' ');
    }
    buffer.write(piece);
    previousLast = piece[piece.length - 1];
  }
  return buffer.toString();
}
