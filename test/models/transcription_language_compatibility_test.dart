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

    test('advertises native auto detection', () {
      expect(
        TranscriptionProvider.localSenseVoice.supportsAutomaticLanguageDetection,
        isTrue,
      );
    });
  });

  group('Moonshine Tiny KO', () {
    test('is Korean-only and never claims auto detection', () {
      expect(
        TranscriptionProvider.localMoonshine.supportsLanguage(
          TranscriptionLanguage.ko,
        ),
        isTrue,
      );
      expect(
        TranscriptionProvider.localMoonshine.supportsLanguage(
          TranscriptionLanguage.auto,
        ),
        isFalse,
      );
      expect(
        TranscriptionProvider.localMoonshine
            .supportsAutomaticLanguageDetection,
        isFalse,
      );
      for (final language in TranscriptionLanguage.values) {
        final expected = language == TranscriptionLanguage.ko;
        expect(
          TranscriptionProvider.localMoonshine.supportsLanguage(language),
          expected,
          reason: 'Moonshine/${language.name}',
        );
      }
    });

    test('auto resolves to Korean only after explicit confirmation', () {
      const provider = TranscriptionProvider.localMoonshine;
      expect(
        provider.autoResolvesTo(TranscriptionLanguage.auto),
        isNull,
      );
      expect(
        provider.autoResolvesTo(
          TranscriptionLanguage.auto,
          koreanConfirmed: true,
        ),
        TranscriptionLanguage.ko,
      );
      expect(
        provider.autoResolvesTo(TranscriptionLanguage.ko),
        TranscriptionLanguage.ko,
      );
      expect(
        provider.effectiveLanguage(
          TranscriptionLanguage.auto,
          koreanConfirmed: true,
        ),
        TranscriptionLanguage.ko,
      );
    });

    test('never silently maps another language to Korean', () {
      const provider = TranscriptionProvider.localMoonshine;
      for (final language in TranscriptionLanguage.values) {
        if (language == TranscriptionLanguage.auto ||
            language == TranscriptionLanguage.ko) {
          continue;
        }
        expect(
          provider.autoResolvesTo(language, koreanConfirmed: true),
          isNull,
          reason: 'Moonshine/${language.name} must not fall back to Korean',
        );
        expect(
          provider.effectiveLanguage(language),
          isNull,
          reason: 'Moonshine/${language.name}',
        );
      }
    });

    test('asks for Korean confirmation only for auto', () {
      const provider = TranscriptionProvider.localMoonshine;
      expect(
        provider.needsKoreanConfirmation(TranscriptionLanguage.auto),
        isTrue,
      );
      expect(
        provider.needsKoreanConfirmation(TranscriptionLanguage.ko),
        isFalse,
      );
      expect(
        provider.needsKoreanConfirmation(TranscriptionLanguage.en),
        isFalse,
      );
      expect(
        TranscriptionProvider.localSenseVoice
            .needsKoreanConfirmation(TranscriptionLanguage.auto),
        isFalse,
      );
    });

    test('auto written to storage stays auto, not Korean', () {
      expect(
        TranscriptionLanguage.fromId(TranscriptionLanguage.auto.storageId),
        TranscriptionLanguage.auto,
      );
    });
  });

  group('Local Whisper Tiny', () {
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

    test('advertises native auto detection', () {
      expect(
        TranscriptionProvider.localWhisper.supportsAutomaticLanguageDetection,
        isTrue,
      );
      expect(
        TranscriptionProvider.localWhisper.effectiveLanguage(
          TranscriptionLanguage.auto,
        ),
        TranscriptionLanguage.auto,
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
