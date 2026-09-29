import 'package:flutter_test/flutter_test.dart';
import 'package:voice_transcriber/models/transcription_provider.dart';
import 'package:voice_transcriber/services/whisper_model_manager.dart';

void main() {
  test('every Whisper model id offered in settings maps to its own size', () {
    final ids = TranscriptionProvider.localWhisper.models;
    expect(ids.length, WhisperModelSize.values.length);
    for (final id in ids) {
      expect(WhisperModelSize.fromModelId(id).modelId, id);
    }
  });

  test('tiny keeps its original folder so earlier installs are still found', () {
    expect(WhisperModelSize.tiny.modelId, 'whisper-tiny-multilingual-int8');
  });

  test('unknown ids fall back to tiny', () {
    expect(WhisperModelSize.fromModelId(null), WhisperModelSize.tiny);
    expect(WhisperModelSize.fromModelId('whisper-large'), WhisperModelSize.tiny);
  });

  test('download sizes match what the settings screen promises', () {
    expect(WhisperModelSize.tiny.downloadMegabytes, 104);
    expect(WhisperModelSize.base.downloadMegabytes, 161);
    expect(WhisperModelSize.small.downloadMegabytes, 375);
  });

  test('each size downloads from its own repository', () {
    expect(WhisperModelSize.base.repository, 'sherpa-onnx-whisper-base');
    expect(WhisperModelSize.small.prefix, 'small');
  });
}
