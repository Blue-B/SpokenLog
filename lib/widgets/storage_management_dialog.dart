import 'package:flutter/material.dart';
import '../services/app_storage_service.dart';

class StorageManagementDialog extends StatefulWidget {
  const StorageManagementDialog({
    super.key,
    required this.onClearSettings,
    this.storage,
    this.useEnglish = false,
    this.onUninstallDecision,
  });
  final AppStorageService? storage;
  final Future<void> Function() onClearSettings;
  final bool useEnglish;

  /// Exit 0 continues removal (including keep-data); exit 1 cancels removal.
  final ValueChanged<bool>? onUninstallDecision;

  @override
  State<StorageManagementDialog> createState() =>
      _StorageManagementDialogState();
}

class _StorageManagementDialogState extends State<StorageManagementDialog> {
  late final _storage = widget.storage ?? AppStorageService();
  late Future<AppStorageUsage> _usage = _storage.usage();
  bool _recordings = false;
  bool _models = false;
  bool _settings = false;
  bool _busy = false;
  String? _notice;
  String _t(String ko, String en) => widget.useEnglish ? en : ko;
  String _size(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  Future<void> _delete() async {
    if (_busy || !(_recordings || _models || _settings)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          _t('선택한 데이터를 완전히 삭제할까요?', 'Permanently delete selected data?'),
        ),
        content: SingleChildScrollView(
          child: Text(
            _t(
              '${_recordings ? '녹음 폴더의 모든 파일, 전사문과 휴지통이 삭제됩니다. 별도 백업이 없으면 복구할 수 없습니다.\n' : ''}'
                  '${_models ? '모델을 다시 사용하려면 다운로드해야 합니다.\n' : ''}'
                  '${_settings ? 'API 키와 앱 설정이 기기에서 삭제됩니다. 서비스에서 발급한 키 자체는 폐기되지 않습니다.\n' : ''}'
                  '외부에 내보낸 파일과 OS 백업은 삭제하지 않습니다.',
              '${_recordings ? 'All files in the recordings folder, transcripts and Trash will be deleted. Recovery requires your own backup.\n' : ''}'
                  '${_models ? 'Models will need to be downloaded again.\n' : ''}'
                  '${_settings ? 'Local credentials and preferences will be removed. API keys are not revoked at the provider.\n' : ''}'
                  'Exported files and OS backups are not removed.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_t('취소', 'Cancel')),
          ),
          FilledButton(
            key: const ValueKey('confirm-storage-delete'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_t('완전 삭제', 'Delete permanently')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      await _storage.delete(recordings: _recordings, models: _models);
      if (_settings) await widget.onClearSettings();
      if (!mounted) return;
      if (widget.onUninstallDecision != null) {
        widget.onUninstallDecision!(true);
        return;
      }
      setState(() {
        _recordings = _models = _settings = false;
        _notice = _t('선택한 데이터를 삭제했습니다.', 'Selected data deleted.');
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice = _t(
            '일부 데이터를 삭제하지 못했습니다. 다른 SpokenLog 창을 닫고 다시 시도하세요. 이미 삭제된 항목은 복구되지 않습니다.',
            'Some data could not be deleted. Close other SpokenLog windows and retry. Items already deleted are not restored.',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _usage = _storage.usage();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uninstall = widget.onUninstallDecision != null;
    return PopScope(
      canPop: !_busy && !uninstall,
      child: AlertDialog(
        title: Text(
          _t(
            uninstall ? '프로그램 제거 전 데이터 선택' : '저장공간 관리',
            uninstall ? 'Data before uninstall' : 'Storage management',
          ),
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: FutureBuilder<AppStorageUsage>(
              future: _usage,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _t(
                          '저장공간을 확인하지 못했습니다. 데이터는 자동으로 삭제되지 않습니다.',
                          'Could not read storage. No data is deleted automatically.',
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            setState(() => _usage = _storage.usage()),
                        child: Text(_t('다시 시도', 'Retry')),
                      ),
                    ],
                  );
                }
                final usage = snapshot.data;
                if (usage == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _t(
                        '기본값은 모두 보존입니다. Windows와 macOS에서는 앱 파일만 지워도 데이터가 남을 수 있으므로 제거 전에 여기서 정리하세요.',
                        'Everything is kept by default. On Windows and macOS, deleting the app alone can leave data behind. Clean it here before removal.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      key: const ValueKey('storage-recordings'),
                      contentPadding: EdgeInsets.zero,
                      value: _recordings,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _recordings = v!),
                      title: Text(_t('녹음과 전사문', 'Recordings and transcripts')),
                      subtitle: Text(
                        '${_size(usage.recordingBytes)} ${_t('(휴지통 포함)', '(including Trash)')}',
                      ),
                    ),
                    CheckboxListTile(
                      key: const ValueKey('storage-models'),
                      contentPadding: EdgeInsets.zero,
                      value: _models,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _models = v!),
                      title: Text(_t('다운로드한 모델', 'Downloaded models')),
                      subtitle: Text(_size(usage.modelBytes)),
                    ),
                    CheckboxListTile(
                      key: const ValueKey('storage-settings'),
                      contentPadding: EdgeInsets.zero,
                      value: _settings,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _settings = v!),
                      title: Text(
                        _t('API 키와 앱 설정', 'API keys and preferences'),
                      ),
                    ),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(_t('저장 위치', 'Storage locations')),
                      children: [
                        SelectableText(
                          '${usage.recordings.path}\n${usage.models.path}',
                        ),
                      ],
                    ),
                    if (_notice != null)
                      Text(_notice!, key: const ValueKey('storage-notice')),
                    FilledButton(
                      key: const ValueKey('delete-selected-storage'),
                      onPressed: _busy || !(_recordings || _models || _settings)
                          ? null
                          : _delete,
                      child: Text(
                        _busy
                            ? _t('정리 중…', 'Cleaning…')
                            : _t(
                                uninstall ? '선택 데이터 삭제 후 계속' : '선택 데이터 삭제',
                                uninstall
                                    ? 'Delete selected and continue'
                                    : 'Delete selected data',
                              ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        actions: [
          if (uninstall)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => widget.onUninstallDecision!(false),
              child: Text(_t('제거 취소', 'Cancel uninstall')),
            ),
          TextButton(
            onPressed: _busy
                ? null
                : () {
                    if (uninstall) {
                      widget.onUninstallDecision!(true);
                    } else {
                      Navigator.pop(context);
                    }
                  },
            child: Text(
              _t(
                uninstall ? '모두 보존하고 계속' : '닫기',
                uninstall ? 'Keep everything and continue' : 'Close',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
