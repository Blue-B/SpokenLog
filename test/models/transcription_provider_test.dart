import 'package:flutter_test/flutter_test.dart';
import 'package:voice_transcriber/models/transcription_language.dart';
import 'package:voice_transcriber/models/transcription_provider.dart';

void main() {
  test('parses provider ids', () {
    expect(
      TranscriptionProvider.fromId('groq'),
      TranscriptionProvider.groq,
    );
    expect(
      TranscriptionProvider.fromId('cloudflare'),
      TranscriptionProvider.cloudflare,
    );
    expect(
      TranscriptionProvider.fromId('local_sensevoice'),
      TranscriptionProvider.localSenseVoice,
    );
    // Moonshine was removed; saved settings move to SenseVoice (Korean-capable).
    expect(
      TranscriptionProvider.fromId('local_moonshine'),
      TranscriptionProvider.localSenseVoice,
    );
    expect(
      TranscriptionProvider.fromId('local_whisper'),
      TranscriptionProvider.localWhisper,
    );
    expect(
      TranscriptionProvider.fromId('unknown'),
      TranscriptionProvider.groq,
    );
  });

  test('provider model lists include expected defaults', () {
    expect(
      TranscriptionProvider.groq.models,
      contains('whisper-large-v3'),
    );
    expect(
      TranscriptionProvider.cloudflare.models.single,
      '@cf/openai/whisper-large-v3-turbo',
    );
    expect(
      TranscriptionProvider.localSenseVoice.models.single,
      'sensevoice-small-int8',
    );
    expect(
      TranscriptionProvider.localWhisper.models,
      [
        'whisper-tiny-multilingual-int8',
        'whisper-base-multilingual-int8',
        'whisper-small-multilingual-int8',
      ],
    );
  });

  test('local providers do not require API keys', () {
    expect(TranscriptionProvider.localSenseVoice.isLocal, isTrue);
    expect(TranscriptionProvider.localWhisper.isLocal, isTrue);
    expect(
      TranscriptionProvider.localSenseVoice.requiresApiKey,
      isFalse,
    );
    expect(
      TranscriptionProvider.localWhisper.requiresApiKey,
      isFalse,
    );
    expect(TranscriptionProvider.groq.requiresApiKey, isTrue);
    expect(TranscriptionProvider.cloudflare.requiresApiKey, isTrue);
  });

  test('providers expose user-facing decision information', () {
    for (final provider in TranscriptionProvider.values) {
      expect(provider.headline, isNotEmpty);
      expect(provider.strength, isNotEmpty);
      expect(provider.tradeoff, isNotEmpty);
      expect(provider.quotaLabel, isNotEmpty);
    }
  });

  test('provider language compatibility is explicit', () {
    expect(
      TranscriptionProvider.localSenseVoice
          .supportsLanguage(TranscriptionLanguage.ko),
      isTrue,
    );
    expect(
      TranscriptionProvider.localSenseVoice
          .supportsLanguage(TranscriptionLanguage.es),
      isFalse,
    );
    expect(
      TranscriptionProvider.localWhisper
          .supportsLanguage(TranscriptionLanguage.es),
      isTrue,
    );
    expect(
      TranscriptionProvider.localWhisper
          .supportsLanguage(TranscriptionLanguage.yue),
      isFalse,
    );
    expect(
      TranscriptionProvider.localWhisper
          .supportsLanguage(TranscriptionLanguage.auto),
      isTrue,
    );
  });
}
