import 'dart:io';

import 'transcription_language.dart';

/// Large Whisper models need a PC's memory and CPU; phones do not list them.
const desktopWhisperModels = ['whisper-turbo-multilingual-int8'];

bool get _isDesktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

enum TranscriptionProvider {
  /// Our server picks the backend; credits come from ads. No user key.
  spokenlogCloud,
  groq,
  cloudflare,
  localSenseVoice,
  localWhisper;

  String get id => switch (this) {
        TranscriptionProvider.spokenlogCloud => 'spokenlog_cloud',
        TranscriptionProvider.groq => 'groq',
        TranscriptionProvider.cloudflare => 'cloudflare',
        TranscriptionProvider.localSenseVoice => 'local_sensevoice',
        TranscriptionProvider.localWhisper => 'local_whisper',
      };

  String get label => switch (this) {
        TranscriptionProvider.spokenlogCloud => 'SpokenLog 클라우드',
        TranscriptionProvider.groq => 'Groq',
        TranscriptionProvider.cloudflare => 'Cloudflare Workers AI',
        TranscriptionProvider.localSenseVoice => 'Local SenseVoice',
        TranscriptionProvider.localWhisper => 'Local Whisper',
      };

  String get shortLabel => switch (this) {
        TranscriptionProvider.spokenlogCloud => 'SpokenLog 클라우드',
        TranscriptionProvider.groq => 'Groq',
        TranscriptionProvider.cloudflare => 'Cloudflare',
        TranscriptionProvider.localSenseVoice => 'SenseVoice',
        TranscriptionProvider.localWhisper => 'Whisper',
      };

  String get categoryLabel => isLocal ? '로컬' : '클라우드';

  String get privacyLabel => isLocal ? '기기 내 처리' : '클라우드 전송';

  bool get isLocal =>
      this == TranscriptionProvider.localSenseVoice ||
      this == TranscriptionProvider.localWhisper;

  bool get requiresApiKey =>
      this == TranscriptionProvider.groq || this == TranscriptionProvider.cloudflare;

  bool supportsLanguage(TranscriptionLanguage language) {
    return switch (this) {
      TranscriptionProvider.localSenseVoice => language.supportedBySenseVoice,
      TranscriptionProvider.localWhisper => language.supportedByWhisper,
      TranscriptionProvider.spokenlogCloud ||
      TranscriptionProvider.groq ||
      TranscriptionProvider.cloudflare => true,
    };
  }

  List<String> get models => switch (this) {
        TranscriptionProvider.spokenlogCloud => const ['spokenlog-cloud'],
        TranscriptionProvider.groq => const [
            'whisper-large-v3',
            'whisper-large-v3-turbo',
          ],
        TranscriptionProvider.cloudflare => const [
            '@cf/openai/whisper-large-v3-turbo',
          ],
        TranscriptionProvider.localSenseVoice => const [
            'sensevoice-small-int8',
          ],
        TranscriptionProvider.localWhisper => [
            'whisper-tiny-multilingual-int8',
            'whisper-base-multilingual-int8',
            'whisper-small-multilingual-int8',
            if (_isDesktop) ...desktopWhisperModels,
          ],
      };

  String modelLabel(String model, {bool useEnglish = false}) {
    if (useEnglish) {
      return switch (model) {
        'spokenlog-cloud' => 'SpokenLog cloud',
        'whisper-large-v3' => 'Whisper Large V3 · Accuracy',
        'whisper-large-v3-turbo' => 'Whisper Large V3 Turbo · Speed',
        '@cf/openai/whisper-large-v3-turbo' => 'Whisper Large V3 Turbo · Cloudflare',
        'sensevoice-small-int8' => 'SenseVoiceSmall INT8 · East Asian languages',
        'whisper-tiny-multilingual-int8' => 'Whisper Tiny INT8 · Fastest, ~104 MB',
        'whisper-base-multilingual-int8' => 'Whisper Base INT8 · Balanced, ~161 MB',
        'whisper-small-multilingual-int8' => 'Whisper Small INT8 · More accurate, ~375 MB',
        'whisper-turbo-multilingual-int8' => 'Whisper Turbo INT8 · PC, most accurate, ~1.04 GB',
        _ => model,
      };
    }
    return switch (model) {
      'spokenlog-cloud' => 'SpokenLog 클라우드',
      'whisper-large-v3' => 'Whisper Large V3 · 정확도 우선',
      'whisper-large-v3-turbo' => 'Whisper Large V3 Turbo · 속도 우선',
      '@cf/openai/whisper-large-v3-turbo' =>
        'Whisper Large V3 Turbo · Cloudflare',
      'sensevoice-small-int8' => 'SenseVoiceSmall INT8 · 동아시아 균형형',
      'whisper-tiny-multilingual-int8' => 'Whisper Tiny INT8 · 가장 빠름, 약 104MB',
      'whisper-base-multilingual-int8' => 'Whisper Base INT8 · 균형형, 약 161MB',
      'whisper-small-multilingual-int8' => 'Whisper Small INT8 · 더 정확함, 약 375MB',
      'whisper-turbo-multilingual-int8' => 'Whisper Turbo INT8 · PC용, 가장 정확함, 약 1.04GB',
      _ => model,
    };
  }

  static TranscriptionProvider fromId(String? value) {
    return switch (value) {
      'spokenlog_cloud' => TranscriptionProvider.spokenlogCloud,
      'cloudflare' => TranscriptionProvider.cloudflare,
      'local_sensevoice' => TranscriptionProvider.localSenseVoice,
      // Moonshine was removed; SenseVoice covers Korean and adds timestamps.
      'local_moonshine' => TranscriptionProvider.localSenseVoice,
      'local_whisper' => TranscriptionProvider.localWhisper,
      _ => TranscriptionProvider.groq,
    };
  }
}
