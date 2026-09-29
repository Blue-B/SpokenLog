// Opt-in check that runs the real local engines on a long recording.
//
// Skipped unless the models and a speech WAV are provided, e.g.:
//   SPOKENLOG_TEST_MODELS=/path/models \       (tiny/, base/, small/, sv/ with the model files)
//   SPOKENLOG_TEST_SPEECH=/path/one.wav \      (short speech clip, 16 kHz mono)
//   SPOKENLOG_TEST_LONG=/path/long.wav \       (that clip repeated, > 60 s)
//   LD_LIBRARY_PATH=<sherpa_onnx_linux>/linux/x64 flutter test <this file>
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_transcriber/models/recording_item.dart';
import 'package:voice_transcriber/models/transcription_language.dart';
import 'package:voice_transcriber/services/sensevoice_model_manager.dart';
import 'package:voice_transcriber/services/sensevoice_transcription_service.dart';
import 'package:voice_transcriber/services/whisper_model_manager.dart';
import 'package:voice_transcriber/services/whisper_transcription_service.dart';

final _models = Platform.environment['SPOKENLOG_TEST_MODELS'];
final _speech = Platform.environment['SPOKENLOG_TEST_SPEECH'];
final _long = Platform.environment['SPOKENLOG_TEST_LONG'];
final _skip = (_models == null || _speech == null || _long == null)
    ? 'set SPOKENLOG_TEST_MODELS / _SPEECH / _LONG to run real inference'
    : false;

RecordingItem _recording(String path) => RecordingItem(
      id: 'test',
      createdAt: DateTime(2026),
      storagePath: File(path).parent.path,
      chunks: [RecordingChunk(audioPath: path, durationMs: 0)],
    );

class _FixedWhisper extends WhisperModelManager {
  _FixedWhisper(WhisperModelSize size, this.dir) : super(size: size);
  final String dir;

  @override
  Future<WhisperModelPaths> paths() async => WhisperModelPaths(
        encoder: '$dir/${size.prefix}-encoder.int8.onnx',
        decoder: '$dir/${size.prefix}-decoder.int8.onnx',
        tokens: '$dir/${size.prefix}-tokens.txt',
      );

  @override
  Future<bool> isInstalled() async => true;
}

class _FixedSenseVoice extends SenseVoiceModelManager {
  _FixedSenseVoice(this.dir);
  final String dir;

  @override
  Future<SenseVoiceModelPaths> paths() async => SenseVoiceModelPaths(
        model: '$dir/model.int8.onnx',
        tokens: '$dir/tokens.txt',
      );

  @override
  Future<bool> isInstalled() async => true;
}

int _words(String text) =>
    RegExp(r'\w+').allMatches(text.toLowerCase()).length;

void main() {
  for (final size in WhisperModelSize.values) {
    test('Whisper ${size.name} transcribes the whole long recording',
        skip: _skip, timeout: const Timeout(Duration(minutes: 10)), () async {
      final service = WhisperTranscriptionService(
        _FixedWhisper(size, '$_models/${size.name}'),
      );
      final short = await service.transcribeRecording(
        recording: _recording(_speech!),
        language: TranscriptionLanguage.en,
      );
      final long = await service.transcribeRecording(
        recording: _recording(_long!),
        language: TranscriptionLanguage.en,
      );

      // ignore: avoid_print
      print('[whisper ${size.name}] short words=${_words(short.text)} '
          'long words=${_words(long.text)} '
          'segments=${long.segments.length}');

      // The clip is repeated 8 times: far more than the first 30 s survives.
      expect(_words(long.text), greaterThan(_words(short.text) * 5));
      expect(long.segments.last.endSeconds, greaterThan(90));
      // Subtitle lines: several per repetition, none longer than a few seconds
      // past the piece limit, and always moving forward in time.
      expect(long.segments.length, greaterThanOrEqualTo(8));
      var previousEnd = 0.0;
      for (final segment in long.segments) {
        expect(segment.startSeconds, greaterThanOrEqualTo(previousEnd - 0.001));
        expect(segment.endSeconds, greaterThan(segment.startSeconds));
        expect(segment.endSeconds - segment.startSeconds, lessThan(13));
        previousEnd = segment.endSeconds;
      }
      // ignore: avoid_print
      print(long.segments
          .take(4)
          .map((s) => '${s.startSeconds.toStringAsFixed(1)}-'
              '${s.endSeconds.toStringAsFixed(1)} ${s.text}')
          .join('\n'));
    });
  }

  test('SenseVoice transcribes the whole long recording',
      skip: _skip, timeout: const Timeout(Duration(minutes: 10)), () async {
    final service =
        SenseVoiceTranscriptionService(_FixedSenseVoice('$_models/sv'));
    final short = await service.transcribeRecording(
      recording: _recording(_speech!),
      language: TranscriptionLanguage.en,
    );
    final long = await service.transcribeRecording(
      recording: _recording(_long!),
      language: TranscriptionLanguage.en,
    );

    // ignore: avoid_print
    print('[sensevoice] short words=${_words(short.text)} '
        'long words=${_words(long.text)} '
        'segments=${long.segments.length}');

    expect(_words(long.text), greaterThan(_words(short.text) * 5));
    expect(long.segments.last.endSeconds, greaterThan(90));
  });
}
