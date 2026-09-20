import 'transcription_language.dart';

enum TranscriptionProvider {
  groq,
  cloudflare,
  localSenseVoice,
  localMoonshine,
  localWhisper;

  String get id => switch (this) {
        TranscriptionProvider.groq => 'groq',
        TranscriptionProvider.cloudflare => 'cloudflare',
        TranscriptionProvider.localSenseVoice => 'local_sensevoice',
        TranscriptionProvider.localMoonshine => 'local_moonshine',
        TranscriptionProvider.localWhisper => 'local_whisper',
      };

  String get label => switch (this) {
        TranscriptionProvider.groq => 'Groq',
        TranscriptionProvider.cloudflare => 'Cloudflare Workers AI',
        TranscriptionProvider.localSenseVoice => 'Local SenseVoice',
        TranscriptionProvider.localMoonshine => 'Local Moonshine KO',
        TranscriptionProvider.localWhisper => 'Local Whisper Tiny',
      };

  String get shortLabel => switch (this) {
        TranscriptionProvider.groq => 'Groq',
        TranscriptionProvider.cloudflare => 'Cloudflare',
        TranscriptionProvider.localSenseVoice => 'SenseVoice',
        TranscriptionProvider.localMoonshine => 'Moonshine',
        TranscriptionProvider.localWhisper => 'Whisper',
      };

  String get categoryLabel => isLocal ? '로컬' : '클라우드';

  String get headline => switch (this) {
        TranscriptionProvider.groq => '정확도와 속도 균형이 좋은 기본 클라우드',
        TranscriptionProvider.cloudflare => 'Groq 한도 소진 시 쓸 수 있는 무료 클라우드 백업',
        TranscriptionProvider.localSenseVoice => '동아시아 언어에 강한 초고속 오프라인 전사',
        TranscriptionProvider.localMoonshine => '한국어 전용 초경량 오프라인 전사',
        TranscriptionProvider.localWhisper => '지원 언어가 넓은 범용 오프라인 전사',
      };

  String get strength => switch (this) {
        TranscriptionProvider.groq =>
          'Whisper Large V3/V3 Turbo를 Groq LPU에서 실행합니다. 긴 녹음과 여러 언어에서 높은 정확도를 기대할 수 있습니다.',
        TranscriptionProvider.cloudflare =>
          'Whisper Large V3 Turbo를 Workers AI에서 실행합니다. Groq와 다른 무료 할당량을 백업으로 활용할 수 있습니다.',
        TranscriptionProvider.localSenseVoice =>
          '한국어·영어·중국어·일본어·광둥어를 매우 빠르게 처리하고 토큰 타임스탬프도 제공합니다.',
        TranscriptionProvider.localMoonshine =>
          '약 69MB의 작은 한국어 전용 모델이라 CPU와 모바일에서도 부담이 적습니다.',
        TranscriptionProvider.localWhisper =>
          'Whisper Tiny Multilingual INT8을 기기에서 실행합니다. SenseVoice/Moonshine이 지원하지 않는 언어의 로컬 fallback으로 적합합니다.',
      };

  String get tradeoff => switch (this) {
        TranscriptionProvider.groq =>
          '무료 한도와 API 키가 필요하며 음성 파일이 Groq 서버로 전송됩니다.',
        TranscriptionProvider.cloudflare =>
          'Account ID와 API Token이 필요하고 무료 할당량은 Workers AI 전체 사용량과 공유됩니다.',
        TranscriptionProvider.localSenseVoice =>
          '지원 언어가 5개로 제한되고 Whisper Large V3보다 정확도가 낮을 수 있습니다. 모델은 약 239MB입니다.',
        TranscriptionProvider.localMoonshine =>
          '한국어만 지원하며 현재 세부 타임스탬프를 제공하지 않습니다.',
        TranscriptionProvider.localWhisper =>
          '약 104MB로 작지만 Tiny 모델이라 Large 계열보다 정확도가 낮고 SenseVoice보다 느릴 수 있습니다.',
      };

  String get quotaLabel => switch (this) {
        TranscriptionProvider.groq =>
          '공식 무료 한도: 20 RPM · 2,000 RPD · 2시간/시간 · 8시간/일',
        TranscriptionProvider.cloudflare =>
          '공식 무료 할당량: 10,000 Neurons/일',
        TranscriptionProvider.localSenseVoice ||
        TranscriptionProvider.localMoonshine ||
        TranscriptionProvider.localWhisper =>
          '사용 한도 없음 · 완전 로컬',
      };

  String get speedLabel => switch (this) {
        TranscriptionProvider.groq => '매우 빠름',
        TranscriptionProvider.cloudflare => '빠름',
        TranscriptionProvider.localSenseVoice => '매우 빠름',
        TranscriptionProvider.localMoonshine => '매우 빠름',
        TranscriptionProvider.localWhisper => '보통',
      };

  String get accuracyLabel => switch (this) {
        TranscriptionProvider.groq => '높음',
        TranscriptionProvider.cloudflare => '높음',
        TranscriptionProvider.localSenseVoice => '중상',
        TranscriptionProvider.localMoonshine => '중상',
        TranscriptionProvider.localWhisper => '보통',
      };

  String get privacyLabel => isLocal ? '기기 내 처리' : '클라우드 전송';

  bool get isLocal =>
      this == TranscriptionProvider.localSenseVoice ||
      this == TranscriptionProvider.localMoonshine ||
      this == TranscriptionProvider.localWhisper;

  bool get requiresApiKey => !isLocal;

  bool supportsLanguage(TranscriptionLanguage language) {
    return switch (this) {
      TranscriptionProvider.localSenseVoice => language.supportedBySenseVoice,
      TranscriptionProvider.localMoonshine => language.supportedByMoonshineKo,
      TranscriptionProvider.groq ||
      TranscriptionProvider.cloudflare ||
      TranscriptionProvider.localWhisper => true,
    };
  }

  List<String> get models => switch (this) {
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
        TranscriptionProvider.localMoonshine => const [
            'moonshine-tiny-ko-quantized',
          ],
        TranscriptionProvider.localWhisper => const [
            'whisper-tiny-multilingual-int8',
          ],
      };

  String modelLabel(String model) {
    return switch (model) {
      'whisper-large-v3' => 'Whisper Large V3 · 정확도 우선',
      'whisper-large-v3-turbo' => 'Whisper Large V3 Turbo · 속도 우선',
      '@cf/openai/whisper-large-v3-turbo' =>
        'Whisper Large V3 Turbo · Cloudflare',
      'sensevoice-small-int8' => 'SenseVoiceSmall INT8 · 동아시아 균형형',
      'moonshine-tiny-ko-quantized' => 'Moonshine Tiny KO · 초경량 한국어',
      'whisper-tiny-multilingual-int8' => 'Whisper Tiny INT8 · 다국어 범용',
      _ => model,
    };
  }

  static TranscriptionProvider fromId(String? value) {
    return switch (value) {
      'cloudflare' => TranscriptionProvider.cloudflare,
      'local_sensevoice' => TranscriptionProvider.localSenseVoice,
      'local_moonshine' => TranscriptionProvider.localMoonshine,
      'local_whisper' => TranscriptionProvider.localWhisper,
      _ => TranscriptionProvider.groq,
    };
  }
}
