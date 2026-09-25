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

  /// Whether the Whisper Tiny Multilingual INT8 model shipped in the app can
  /// be told this language explicitly.
  ///
  /// Verified against the model metadata of `sherpa-onnx-whisper-tiny`
  /// (v1.13.8): its language vocabulary is the standard Whisper set and does
  /// **not** contain `yue`. Passing it makes sherpa-onnx abort the whole
  /// process instead of raising a Dart error, so Cantonese is rejected here.
  /// [TranscriptionLanguage.auto] is allowed and uses Whisper's own detector.
  bool get supportedByWhisperTiny => this != TranscriptionLanguage.yue;

  /// Whether this exact selection can be handed to the Korean-only Moonshine
  /// Tiny KO model.
  ///
  /// This is deliberately `ko`-only. Moonshine Tiny KO has no language token
  /// or detector, so [TranscriptionLanguage.auto] cannot be truthfully
  /// advertised here even though the audio is usually Korean.
  bool get supportedByMoonshineKo => this == TranscriptionLanguage.ko;

  /// Whether this language is only a stand-in for an engine that has no
  /// explicit preference for it.
  ///
  /// [TranscriptionLanguage.auto] means "let the engine detect the language".
  /// Engines without detection (Moonshine Tiny KO) must not be auto-selected
  /// for another language, and an unknown language must never be silently
  /// treated as Korean.
  bool get isAutomaticDetection => this == TranscriptionLanguage.auto;

  static TranscriptionLanguage fromId(String? value) {
    for (final language in TranscriptionLanguage.values) {
      if (language.storageId == value) return language;
    }
    return TranscriptionLanguage.auto;
  }
}
