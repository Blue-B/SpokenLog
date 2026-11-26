import 'package:flutter/material.dart';

/// The settings list. Every row says in plain words what it is for and shows
/// its current state on the right, so nobody has to open it to find out.
class AppSettingsSheet extends StatelessWidget {
  const AppSettingsSheet({
    super.key,
    required this.onGroq,
    required this.onCloudflare,
    required this.onLocalModels,
    required this.onTranscription,
    required this.onDisplayLanguage,
    this.useEnglish = false,
    this.onStorage,
    this.onLicenses,
    this.onAiConnection,
    this.speechSummary,
    this.languageLabel,
    this.groqConnected,
    this.cloudflareConnected,
  });

  final VoidCallback onGroq;
  final VoidCallback onCloudflare;
  final VoidCallback onLocalModels;
  final VoidCallback onTranscription;
  final VoidCallback onDisplayLanguage;
  final bool useEnglish;
  final VoidCallback? onStorage;
  final VoidCallback? onLicenses;
  final VoidCallback? onAiConnection;

  /// e.g. "On this phone · SenseVoice · Auto detect".
  final String? speechSummary;

  /// The app's display language, e.g. "한국어".
  final String? languageLabel;
  final bool? groqConnected;
  final bool? cloudflareConnected;

  String _t(String ko, String en) => useEnglish ? en : ko;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    Widget entry(String id, IconData icon, String title, String subtitle,
        VoidCallback action, {String? value, bool? on}) {
      return ListTile(
        key: ValueKey(id),
        contentPadding: const EdgeInsets.fromLTRB(20, 4, 14, 4),
        leading: Icon(icon, color: scheme.onSurfaceVariant),
        title: Text(title, style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (on != null)
              Text(
                on ? _t('연결됨', 'Connected') : _t('연결 안 됨', 'Not connected'),
                style: text.labelMedium?.copyWith(
                  color: on ? scheme.primary : scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              )
            else if (value != null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
              ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: scheme.outline),
          ],
        ),
        onTap: action,
      );
    }

    Widget heading(String title, [String? note]) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: text.titleSmall?.copyWith(
                      color: scheme.primary, fontWeight: FontWeight.w700)),
              if (note != null) ...[
                const SizedBox(height: 2),
                Text(note,
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ],
          ),
        );

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
            child: Row(children: [
              Expanded(
                child: Text(_t('설정', 'Settings'),
                    style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              ),
              IconButton(
                tooltip: _t('닫기', 'Close'),
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ]),
          ),
          Expanded(
            child: ListView(
              children: [
                heading(_t('음성을 글로 바꾸기', 'Speech to text')),
                entry('settings-transcription', Icons.record_voice_over_outlined,
                    _t('글로 바꾸는 방법', 'How speech becomes text'),
                    speechSummary ??
                        _t('어디서 처리할지, 녹음 언어, 말한 사람 나누기',
                            'Where it runs, spoken language, speakers'),
                    onTranscription),
                entry('settings-local-models', Icons.download_for_offline_outlined,
                    _t('음성 모델 받기', 'Speech models'),
                    _t('인터넷 없이 쓰려면 한 번 받아 두세요',
                        'Download once to work without internet'),
                    onLocalModels),
                heading(
                  _t('온라인 서비스 (선택)', 'Online services (optional)'),
                  _t('기기에서 처리한다면 연결하지 않아도 됩니다.',
                      'Not needed if you transcribe on this device.'),
                ),
                entry('settings-groq', Icons.bolt_rounded, 'Groq',
                    _t('빠르고 정확한 무료 서비스 · 키 필요',
                        'Fast, accurate, free tier · needs a key'),
                    onGroq,
                    on: groqConnected),
                entry('settings-cloudflare', Icons.cloud_outlined, 'Cloudflare',
                    _t('무료 사용량 제공 · 계정 정보 필요',
                        'Free daily allowance · needs account details'),
                    onCloudflare,
                    on: cloudflareConnected),
                if (onAiConnection != null)
                  entry('settings-ai-connection', Icons.hub_outlined,
                      _t('AI 연결 (MCP)', 'AI connection (MCP)'),
                      _t('Claude, ChatGPT 등이 내 녹음을 찾아 읽게 하기',
                          'Let Claude, ChatGPT and others search your recordings'),
                      onAiConnection!),
                heading(_t('앱', 'App')),
                entry('settings-display-language', Icons.translate_rounded,
                    _t('화면 언어', 'Display language'),
                    _t('메뉴와 버튼에 쓰는 언어', 'Language of menus and buttons'),
                    onDisplayLanguage,
                    value: languageLabel),
                if (onStorage != null)
                  entry('settings-storage', Icons.cleaning_services_outlined,
                      _t('저장공간 정리', 'Free up space'),
                      _t('녹음, 모델이 쓰는 용량 보기와 지우기',
                          'See and delete what recordings and models use'),
                      onStorage!),
                if (onLicenses != null)
                  entry('settings-licenses', Icons.info_outline_rounded,
                      _t('오픈소스 라이선스', 'Open-source licenses'),
                      _t('앱과 음성 모델의 출처', 'Where the app and models come from'),
                      onLicenses!),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
