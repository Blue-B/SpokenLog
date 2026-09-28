import 'package:flutter/material.dart';

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
  });

  final VoidCallback onGroq;
  final VoidCallback onCloudflare;
  final VoidCallback onLocalModels;
  final VoidCallback onTranscription;
  final VoidCallback onDisplayLanguage;
  final bool useEnglish;
  final VoidCallback? onStorage;

  String _t(String ko, String en) => useEnglish ? en : ko;

  @override
  Widget build(BuildContext context) {
    Widget entry(String id, IconData icon, String title, String subtitle,
        VoidCallback action) {
      return ListTile(
        key: ValueKey(id),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: action,
      );
    }

    Widget heading(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 6),
          child: Text(text,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary)),
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
                    style: Theme.of(context).textTheme.headlineSmall),
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
                heading(_t('앱', 'App')),
                entry('settings-display-language', Icons.translate_rounded,
                    _t('표시 언어', 'Display language'),
                    _t('한국어 · English · 시스템 기본값',
                        '한국어 · English · System default'),
                    onDisplayLanguage),
                if (onStorage != null)
                  entry('settings-storage', Icons.storage_rounded,
                      _t('저장공간 관리', 'Storage management'),
                      _t('녹음, 모델 정리와 프로그램 제거 안내',
                          'Recordings, models and uninstall guidance'), onStorage!),
                heading(_t('음성 인식', 'Speech recognition')),
                entry('settings-local-models', Icons.download_for_offline_outlined,
                    _t('로컬 모델 관리', 'Local models'),
                    _t('모델 다운로드·삭제, 화자 구분',
                        'Download or remove models; speaker separation'),
                    onLocalModels),
                entry('settings-transcription', Icons.tune_rounded,
                    _t('전사 방식과 녹음 언어', 'Transcription and audio language'),
                    _t('엔진 선택, 모델, 음성 언어',
                        'Choose an engine, model and spoken language'),
                    onTranscription),
                heading(_t('클라우드 연결', 'Cloud connections')),
                entry('settings-groq', Icons.key_outlined, 'Groq',
                    _t('API 키 등록 및 변경', 'Add or change your API key'), onGroq),
                entry('settings-cloudflare', Icons.cloud_outlined, 'Cloudflare',
                    _t('Account ID와 API Token', 'Account ID and API token'),
                    onCloudflare),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
