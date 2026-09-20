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

  bool get supportedByMoonshineKo => this == TranscriptionLanguage.ko;

  static TranscriptionLanguage fromId(String? value) {
    for (final language in TranscriptionLanguage.values) {
      if (language.storageId == value) return language;
    }
    return TranscriptionLanguage.auto;
  }
}
