import 'dart:io';
import 'dart:isolate';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../models/recording_item.dart';
import '../models/transcription_error.dart';
import '../models/transcription_language.dart';
import '../models/transcription_result.dart';
import 'local_wav_input.dart';
import 'whisper_model_manager.dart';

class WhisperTranscriptionService {
  WhisperTranscriptionService(this._modelManager);

  final WhisperModelManager _modelManager;

  Future<TranscriptionResult> transcribeRecording({
    required RecordingItem recording,
    required TranscriptionLanguage language,
  }) async {
    if (recording.chunks.isEmpty) {
      throw const TranscriptionException(
        kind: TranscriptionErrorKind.invalidRequest,
        provider: 'Local Whisper',
        message: '전사할 녹음 파일이 없습니다.',
      );
    }

    final unsupported = recording.chunks
        .where((chunk) => !chunk.audioPath.toLowerCase().endsWith('.wav'))
        .toList();
    if (unsupported.isNotEmpty) {
      throw const TranscriptionException(
        kind: TranscriptionErrorKind.unsupportedFormat,
        provider: 'Local Whisper',
        message:
            '로컬 Whisper는 WAV 녹음만 지원합니다. '
            '가져온 M4A/MP3/MP4/WebM 파일은 클라우드 전사를 사용해 주세요.',
      );
    }

    await ensureLocalWavInputs(
      audioPaths: recording.audioPaths,
      provider: 'Local Whisper',
      containerHint: 'M4A/MP3/MP4/WebM 파일은 클라우드 전사를 사용해 주세요.',
    );

    if (!language.supportedByWhisperTiny) {
      throw TranscriptionException(
        kind: TranscriptionErrorKind.invalidRequest,
        provider: 'Local Whisper',
        message:
            'Whisper Tiny 다국어 모델에는 ${language.label} 언어 토큰이 없습니다. '
            '자동 감지를 사용하거나 SenseVoice를 선택해 주세요.',
      );
    }

    if (!await _modelManager.isInstalled()) {
      throw const TranscriptionException(
        kind: TranscriptionErrorKind.modelNotInstalled,
        provider: 'Local Whisper',
        message:
            'Whisper Tiny Multilingual 모델이 설치되어 있지 않습니다. '
            '전사 설정에서 모델을 먼저 다운로드해 주세요.',
      );
    }

    final paths = await _modelManager.paths();
    final request = _WhisperDecodeRequest(
      encoderPath: paths.encoder,
      decoderPath: paths.decoder,
      tokensPath: paths.tokens,
      language: language.cloudCode ?? '',
      audioPaths: recording.audioPaths,
      numThreads: Platform.numberOfProcessors.clamp(1, 4).toInt(),
    );

    try {
      final decoded = await Isolate.run(
        () => _decodeWhisperBatch(request),
      );

      final texts = <String>[];
      final segments = <TranscriptSegment>[];
      var offsetSeconds = 0.0;

      for (final chunk in decoded) {
        final text = chunk['text']?.toString().trim() ?? '';
        if (text.isNotEmpty) texts.add(text);

        final rawSegments = chunk['segments'];
        if (rawSegments is List) {
          for (final raw in rawSegments.whereType<Map>()) {
            segments.add(
              TranscriptSegment.fromJson(
                Map<String, dynamic>.from(raw),
              ).shifted(offsetSeconds),
            );
          }
        }

        offsetSeconds += (chunk['duration'] as num?)?.toDouble() ?? 0;
      }

      final text = texts.join('\n\n').trim();
      if (text.isEmpty) {
        throw const TranscriptionException(
          kind: TranscriptionErrorKind.unknown,
          provider: 'Local Whisper',
          message: 'Whisper에서 전사 결과를 만들지 못했습니다.',
        );
      }

      return TranscriptionResult(
        text: text,
        segments: segments,
        durationSeconds: offsetSeconds > 0
            ? offsetSeconds
            : recording.durationMs > 0
                ? recording.durationMs / 1000
                : null,
      );
    } on TranscriptionException {
      rethrow;
    } catch (e) {
      throw TranscriptionException(
        kind: TranscriptionErrorKind.unknown,
        provider: 'Local Whisper',
        message: 'Whisper 로컬 전사 중 오류가 발생했습니다.',
        detail: e.toString(),
      );
    }
  }
}

class _WhisperDecodeRequest {
  const _WhisperDecodeRequest({
    required this.encoderPath,
    required this.decoderPath,
    required this.tokensPath,
    required this.language,
    required this.audioPaths,
    required this.numThreads,
  });

  final String encoderPath;
  final String decoderPath;
  final String tokensPath;
  final String language;
  final List<String> audioPaths;
  final int numThreads;
}

List<Map<String, dynamic>> _decodeWhisperBatch(
  _WhisperDecodeRequest request,
) {
  sherpa.initBindings();

  final whisper = sherpa.OfflineWhisperModelConfig(
    encoder: request.encoderPath,
    decoder: request.decoderPath,
    language: request.language,
    task: 'transcribe',
    enableTokenTimestamps: true,
  );

  final model = sherpa.OfflineModelConfig(
    whisper: whisper,
    tokens: request.tokensPath,
    modelType: 'whisper',
    debug: false,
    numThreads: request.numThreads,
  );

  final recognizer = sherpa.OfflineRecognizer(
    sherpa.OfflineRecognizerConfig(model: model),
  );

  final outputs = <Map<String, dynamic>>[];

  try {
    for (final path in request.audioPaths) {
      final wave = sherpa.readWave(path);
      ensureDecodedWaveUsable(
        sampleCount: wave.samples.length,
        sampleRate: wave.sampleRate,
        provider: 'Local Whisper',
      );
      final durationSeconds = wave.sampleRate > 0
          ? wave.samples.length / wave.sampleRate
          : 0.0;
      final stream = recognizer.createStream();

      try {
        stream.acceptWaveform(
          samples: wave.samples,
          sampleRate: wave.sampleRate,
        );
        recognizer.decode(stream);
        final result = recognizer.getResult(stream);

        final tokens = List<String>.from(result.tokens);
        final timestamps =
            result.timestamps.map((value) => value.toDouble()).toList();

        outputs.add({
          'text': result.text.trim(),
          'duration': durationSeconds,
          'segments': _buildWhisperTimestampSegments(
            tokens: tokens,
            timestamps: timestamps,
            durationSeconds: durationSeconds,
          ),
        });
      } finally {
        stream.free();
      }
    }
  } finally {
    recognizer.free();
  }

  return outputs;
}

List<Map<String, dynamic>> _buildWhisperTimestampSegments({
  required List<String> tokens,
  required List<double> timestamps,
  required double durationSeconds,
}) {
  if (tokens.isEmpty ||
      timestamps.isEmpty ||
      tokens.length != timestamps.length) {
    return const [];
  }

  final segments = <Map<String, dynamic>>[];
  final buffer = StringBuffer();
  double? segmentStart;
  var segmentEnd = 0.0;
  var previousTimestamp = -1.0;

  void flush() {
    final start = segmentStart;
    final text = _cleanWhisperText(buffer.toString());
    if (start == null || text.isEmpty) {
      buffer.clear();
      segmentStart = null;
      return;
    }

    final safeEnd = segmentEnd > start
        ? segmentEnd
        : (start + 0.5).clamp(0.0, durationSeconds).toDouble();

    segments.add({
      'start': start,
      'end': safeEnd,
      'text': text,
    });
    buffer.clear();
    segmentStart = null;
  }

  for (var i = 0; i < tokens.length; i++) {
    final token = _cleanWhisperToken(tokens[i]);
    if (token.isEmpty) continue;

    final start = timestamps[i].clamp(0.0, durationSeconds).toDouble();
    final next = i + 1 < timestamps.length
        ? timestamps[i + 1].clamp(start, durationSeconds).toDouble()
        : durationSeconds > start
            ? durationSeconds
            : start + 0.5;

    final hasLargeGap =
        previousTimestamp >= 0 && start - previousTimestamp > 1.5;
    final tooLong = segmentStart != null && start - segmentStart! >= 7.0;

    if ((hasLargeGap || tooLong) && buffer.isNotEmpty) {
      flush();
    }

    segmentStart ??= start;
    buffer.write(token);
    segmentEnd = next;
    previousTimestamp = start;

    if (_endsWhisperSentence(token)) {
      flush();
    }
  }

  if (buffer.isNotEmpty) flush();
  return segments;
}

String _cleanWhisperToken(String token) {
  return token
      .replaceAll(RegExp(r'<\|[^>]+\|>'), '')
      .replaceAll('Ġ', ' ')
      .replaceAll('▁', ' ')
      .replaceAll('Ċ', '\n');
}

String _cleanWhisperText(String value) {
  return value
      .replaceAll(RegExp(r'<\|[^>]+\|>'), '')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\s*\n\s*'), ' ')
      .trim();
}

bool _endsWhisperSentence(String token) {
  final value = token.trimRight();
  return value.endsWith('.') ||
      value.endsWith('?') ||
      value.endsWith('!') ||
      value.endsWith('。') ||
      value.endsWith('？') ||
      value.endsWith('！');
}
