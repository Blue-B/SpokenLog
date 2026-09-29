import 'package:flutter_test/flutter_test.dart';
import 'package:voice_transcriber/models/transcription_language.dart';
import 'package:voice_transcriber/models/transcription_provider.dart';

void main() {
  group('SenseVoice', () {
    test('supports auto plus the five documented languages only', () {
      const supported = {
        TranscriptionLanguage.auto,
        TranscriptionLanguage.ko,
        TranscriptionLanguage.en,
        TranscriptionLanguage.ja,
        TranscriptionLanguage.zh,
        TranscriptionLanguage.yue,
      };
      for (final language in TranscriptionLanguage.values) {
        expect(
          TranscriptionProvider.localSenseVoice.supportsLanguage(language),
          supported.contains(language),
          reason: 'SenseVoice/${language.name}',
        );
      }
    });

    test('accepts auto detection', () {
      expect(
        TranscriptionProvider.localSenseVoice
            .supportsLanguage(TranscriptionLanguage.auto),
        isTrue,
      );
    });
  });

  group('Language storage', () {
    test('auto written to storage stays auto, not Korean', () {
      expect(
        TranscriptionLanguage.fromId(TranscriptionLanguage.auto.storageId),
        TranscriptionLanguage.auto,
      );
    });
  });

  group('Local Whisper', () {
    test('accepts Whisper language tokens but rejects yue', () {
      // The sherpa-onnx-whisper-tiny metadata language list does not include
      // yue, and passing it aborts the native process.
      expect(
        TranscriptionProvider.localWhisper.supportsLanguage(
          TranscriptionLanguage.yue,
        ),
        isFalse,
      );
      expect(
        TranscriptionProvider.localWhisper.supportsLanguage(
          TranscriptionLanguage.ko,
        ),
        isTrue,
      );
      expect(
        TranscriptionProvider.localWhisper.supportsLanguage(
          TranscriptionLanguage.auto,
        ),
        isTrue,
      );
    });

    test('accepts auto detection', () {
      expect(
        TranscriptionProvider.localWhisper
            .supportsLanguage(TranscriptionLanguage.auto),
        isTrue,
      );
    });

    test('every app language except yue maps to a Whisper token', () {
      // Verified against the model metadata: all_language_codes of
      // csukuangfj/sherpa-onnx-whisper-tiny.
      const whisperCodes = {
        'sq', 'ml', 'de', 'hi', 'uz', 'zh', 'nl', 'he', 'sk', 'gl', 'lv',
        'ar', 'tr', 'haw', 'gu', 'si', 'be', 'bo', 'tk', 'sr', 'mr', 'pt',
        'mn', 'sa', 'tg', 'pa', 'sv', 'as', 'sl', 'su', 'ba', 'hu', 'ln',
        'br', 'es', 'ca', 'bg', 'hy', 'th', 'yo', 'it', 'da', 'oc', 'ro',
        'ta', 'is', 'bs', 'cs', 'lb', 'my', 'sd', 'fo', 'ne', 'ha', 'te',
        'mi', 'cy', 'el', 'mg', 'af', 'yi', 'kn', 'ms', 'so', 'nn', 'tt',
        'en', 'tl', 'pl', 'ko', 'az', 'hr', 'am', 'id', 'uk', 'ps', 'no',
        'eu', 'kk', 'km', 'lo', 'sn', 'fr', 'mk', 'la', 'jw', 'fi', 'bn',
        'lt', 'vi', 'ka', 'mt', 'sw', 'ur', 'ru', 'ja', 'fa', 'ht', 'et',
      };
      for (final language in TranscriptionLanguage.values) {
        final code = language.cloudCode;
        if (code == null) continue;
        if (language == TranscriptionLanguage.yue) {
          expect(whisperCodes.contains(code), isFalse);
          continue;
        }
        expect(
          whisperCodes.contains(code),
          isTrue,
          reason: '${language.name} ($code) is not a Whisper token',
        );
      }
    });
  });

  group('cloud providers', () {
    test('accept every app language including yue', () {
      for (final provider in [
        TranscriptionProvider.groq,
        TranscriptionProvider.cloudflare,
      ]) {
        for (final language in TranscriptionLanguage.values) {
          expect(
            provider.supportsLanguage(language),
            isTrue,
            reason: '${provider.name}/${language.name}',
          );
        }
      }
    });
  });
}
