enum TranscriptionLanguage {
  auto,
  ko,
  en,
  ja,
  zh,
  yue,
  es,
  fr,
  de,
  pt,
  it,
  ru,
  ar,
  hi,
  vi,
  uk,
  id,
  th,
  tr,
  nl,
  pl;

  String get storageId => this == TranscriptionLanguage.id ? 'id' : name;

  String get label => switch (this) {
        TranscriptionLanguage.auto => '자동 감지',
        TranscriptionLanguage.ko => '한국어',
        TranscriptionLanguage.en => 'English',
        TranscriptionLanguage.ja => '日本語',
        TranscriptionLanguage.zh => '中文',
        TranscriptionLanguage.yue => '廣東話',
        TranscriptionLanguage.es => 'Español',
        TranscriptionLanguage.fr => 'Français',
        TranscriptionLanguage.de => 'Deutsch',
        TranscriptionLanguage.pt => 'Português',
        TranscriptionLanguage.it => 'Italiano',
        TranscriptionLanguage.ru => 'Русский',
        TranscriptionLanguage.ar => 'العربية',
        TranscriptionLanguage.hi => 'हिन्दी',
        TranscriptionLanguage.vi => 'Tiếng Việt',
        TranscriptionLanguage.uk => 'Українська',
        TranscriptionLanguage.id => 'Bahasa Indonesia',
        TranscriptionLanguage.th => 'ไทย',
        TranscriptionLanguage.tr => 'Türkçe',
        TranscriptionLanguage.nl => 'Nederlands',
        TranscriptionLanguage.pl => 'Polski',
      };

  String displayLabel({bool useEnglish = false}) =>
      useEnglish && this == TranscriptionLanguage.auto ? 'Auto detect' : label;

  String? get cloudCode => switch (this) {
        TranscriptionLanguage.auto => null,
        TranscriptionLanguage.id => 'id',
        _ => name,
      };

  String get senseVoiceCode => switch (this) {
        TranscriptionLanguage.auto => 'auto',
        TranscriptionLanguage.ko => 'ko',
        TranscriptionLanguage.en => 'en',
        TranscriptionLanguage.ja => 'ja',
        TranscriptionLanguage.zh => 'zh',
        TranscriptionLanguage.yue => 'yue',
        _ => '',
      };

  bool get supportedBySenseVoice => const {
        TranscriptionLanguage.auto,
        TranscriptionLanguage.ko,
        TranscriptionLanguage.en,
        TranscriptionLanguage.ja,
        TranscriptionLanguage.zh,
        TranscriptionLanguage.yue,
      }.contains(this);

  /// Whether the multilingual Whisper models (Tiny, Base and Small INT8) can be
  /// told this language explicitly.
  ///
  /// Verified against the model metadata of `sherpa-onnx-whisper-tiny`, `-base`
  /// and `-small` (v1.13.8): each lists the same 99 standard Whisper codes and
  /// none contains `yue`. Passing it makes sherpa-onnx abort the whole process
  /// instead of raising a Dart error, so Cantonese is rejected here.
  /// [TranscriptionLanguage.auto] is allowed and uses Whisper's own detector.
  bool get supportedByWhisper => this != TranscriptionLanguage.yue;

  static TranscriptionLanguage fromId(String? value) {
    for (final language in TranscriptionLanguage.values) {
      if (language.storageId == value) return language;
    }
    return TranscriptionLanguage.auto;
  }
}
