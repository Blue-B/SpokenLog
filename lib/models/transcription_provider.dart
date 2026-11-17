import 'transcription_language.dart';

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

  String get headline => switch (this) {
        TranscriptionProvider.spokenlogCloud => '키 없이 바로 쓰는 빠르고 정확한 클라우드 전사',
        TranscriptionProvider.groq => '정확도와 속도 균형이 좋은 기본 클라우드',
        TranscriptionProvider.cloudflare => 'Groq 한도 소진 시 쓸 수 있는 무료 클라우드 백업',
        TranscriptionProvider.localSenseVoice => '동아시아 언어에 강한 초고속 오프라인 전사',
        TranscriptionProvider.localWhisper => '지원 언어가 넓은 범용 오프라인 전사',
      };

  String get strength => switch (this) {
        TranscriptionProvider.spokenlogCloud =>
          'API 키나 연결 설정 없이 Google 계정으로 로그인해 바로 씁니다. 광고를 보면 클라우드 전사 시간을 받습니다.',
        TranscriptionProvider.groq =>
          'Whisper Large V3/V3 Turbo를 Groq LPU에서 실행합니다. 긴 녹음과 여러 언어에서 높은 정확도를 기대할 수 있습니다.',
        TranscriptionProvider.cloudflare =>
          'Whisper Large V3 Turbo를 Workers AI에서 실행합니다. Groq와 다른 무료 할당량을 백업으로 활용할 수 있습니다.',
        TranscriptionProvider.localSenseVoice =>
          '한국어·영어·중국어·일본어·광둥어를 매우 빠르게 처리하고 토큰 타임스탬프도 제공합니다.',
        TranscriptionProvider.localWhisper =>
          'Whisper Multilingual INT8(Tiny, Base, Small 중 선택)을 기기에서 실행합니다. SenseVoice가 지원하지 않는 언어의 로컬 선택지로 적합합니다.',
      };

  String get tradeoff => switch (this) {
        TranscriptionProvider.spokenlogCloud =>
          '인터넷이 필요하고 사용 시간만큼 크레딧이 차감됩니다. 녹음은 전사를 위해 SpokenLog 서버와 처리 업체로 전송되며 저장되지 않습니다.',
        TranscriptionProvider.groq =>
          '무료 한도와 API 키가 필요하며 음성 파일이 Groq 서버로 전송됩니다.',
        TranscriptionProvider.cloudflare =>
          'Account ID와 API Token이 필요하고 무료 할당량은 Workers AI 전체 사용량과 공유됩니다.',
        TranscriptionProvider.localSenseVoice =>
          '지원 언어가 5개로 제한되고 Whisper Large V3보다 정확도가 낮을 수 있습니다. 모델은 약 239MB입니다.',
        TranscriptionProvider.localWhisper =>
          'Tiny 약 104MB, Base 약 161MB, Small 약 375MB이며 클수록 정확하지만 느립니다. 그래도 Large 계열보다 정확도가 낮고 SenseVoice보다 느릴 수 있습니다. 광둥어(yue)는 Whisper 다국어 토큰에 없어 자동 감지나 SenseVoice를 사용해야 합니다.',
      };

  String get quotaLabel => switch (this) {
        TranscriptionProvider.spokenlogCloud => '광고 1회당 전사 시간 지급',
        TranscriptionProvider.groq =>
          '공식 무료 한도: 20 RPM · 2,000 RPD · 2시간/시간 · 8시간/일',
        TranscriptionProvider.cloudflare =>
          '공식 무료 할당량: 10,000 Neurons/일',
        TranscriptionProvider.localSenseVoice ||
        TranscriptionProvider.localWhisper =>
          '사용 한도 없음 · 완전 로컬',
      };

  String get speedLabel => switch (this) {
        TranscriptionProvider.spokenlogCloud || TranscriptionProvider.groq => '매우 빠름',
        TranscriptionProvider.cloudflare => '빠름',
        TranscriptionProvider.localSenseVoice => '매우 빠름',
        TranscriptionProvider.localWhisper => '보통',
      };

  String get accuracyLabel => switch (this) {
        TranscriptionProvider.spokenlogCloud ||
        TranscriptionProvider.groq ||
        TranscriptionProvider.cloudflare => '높음',
        TranscriptionProvider.localSenseVoice => '중상',
        TranscriptionProvider.localWhisper => '보통',
      };

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
        TranscriptionProvider.localWhisper => const [
            'whisper-tiny-multilingual-int8',
            'whisper-base-multilingual-int8',
            'whisper-small-multilingual-int8',
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
        'whisper-small-multilingual-int8' => 'Whisper Small INT8 · Most accurate, ~375 MB',
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
      'whisper-small-multilingual-int8' => 'Whisper Small INT8 · 가장 정확함, 약 375MB',
      _ => model,
    };
  }

  String headlineFor(bool english) => !english ? headline : switch (this) {
    TranscriptionProvider.spokenlogCloud => 'Fast, accurate cloud transcription with no API key',
    TranscriptionProvider.groq => 'Cloud transcription with balanced speed and accuracy',
    TranscriptionProvider.cloudflare => 'An alternative cloud quota when Groq is unavailable',
    TranscriptionProvider.localSenseVoice => 'Fast offline transcription for East Asian languages',
    TranscriptionProvider.localWhisper => 'General-purpose multilingual offline transcription',
  };

  String strengthFor(bool english) => !english ? strength : switch (this) {
    TranscriptionProvider.spokenlogCloud => 'Sign in with Google and start; no API key or setup. Watch an ad to get cloud time.',
    TranscriptionProvider.groq => 'Runs Whisper Large V3/V3 Turbo on Groq. Suitable for long recordings and multilingual transcription.',
    TranscriptionProvider.cloudflare => 'Runs Whisper Large V3 Turbo on Workers AI, with a quota separate from Groq.',
    TranscriptionProvider.localSenseVoice => 'Supports Korean, English, Chinese, Japanese and Cantonese, with token timestamps.',
    TranscriptionProvider.localWhisper => 'Runs Whisper Multilingual INT8 (Tiny, Base or Small) on your device for languages beyond SenseVoice.',
  };

  String tradeoffFor(bool english) => !english ? tradeoff : switch (this) {
    TranscriptionProvider.spokenlogCloud => 'Needs internet and uses credits per audio second. Audio is sent to the SpokenLog server and its processors for transcription and is not stored.',
    TranscriptionProvider.groq => 'Requires an API key and is subject to quotas. Audio is sent to Groq.',
    TranscriptionProvider.cloudflare => 'Requires an Account ID and API token. The free quota is shared across Workers AI.',
    TranscriptionProvider.localSenseVoice => 'Limited to five languages; may be less accurate than Whisper Large V3. About 239 MB.',
    TranscriptionProvider.localWhisper => 'Tiny about 104 MB, Base about 161 MB, Small about 375 MB. Larger is more accurate but slower, and still less accurate than Large models. For Cantonese, use Auto or SenseVoice.',
  };

  String quotaLabelFor(bool english) => !english ? quotaLabel : switch (this) {
    TranscriptionProvider.spokenlogCloud => 'Cloud time per rewarded ad',
    TranscriptionProvider.groq => 'Free limits: 20 RPM · 2,000 RPD · 2 audio hours/hour · 8/day',
    TranscriptionProvider.cloudflare => 'Free quota: 10,000 Neurons/day',
    _ => 'No usage quota · Fully local',
  };

  String speedLabelFor(bool english) => !english ? speedLabel : switch (this) {
    TranscriptionProvider.cloudflare => 'Fast',
    TranscriptionProvider.localWhisper => 'Moderate',
    _ => 'Very fast',
  };

  String accuracyLabelFor(bool english) => !english ? accuracyLabel : switch (this) {
    TranscriptionProvider.spokenlogCloud ||
    TranscriptionProvider.groq ||
    TranscriptionProvider.cloudflare => 'High',
    TranscriptionProvider.localWhisper => 'Moderate',
    _ => 'Medium-high',
  };

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
