import 'package:flutter/material.dart';

/// One downloadable on-device model shown in [LocalModelsDialog].
class LocalModelEntry {
  const LocalModelEntry({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.isInstalled,
    required this.download,
    required this.delete,
  });

  final String id;
  final String title;
  final String subtitle;
  final Future<bool> Function() isInstalled;
  final Future<void> Function(void Function(double? progress) onProgress)
      download;
  final Future<void> Function() delete;
}

/// Download and remove on-device models. Choosing the engine lives in the
/// transcription settings, not here.
class LocalModelsDialog extends StatefulWidget {
  const LocalModelsDialog({
    super.key,
    required this.models,
    this.useEnglish = false,
  });

  final List<LocalModelEntry> models;
  final bool useEnglish;

  @override
  State<LocalModelsDialog> createState() => _LocalModelsDialogState();
}

class _LocalModelsDialogState extends State<LocalModelsDialog> {
  final _installed = <String, bool>{};
  String? _busyId;
  double? _progress;
  String? _error;

  String _t(String ko, String en) => widget.useEnglish ? en : ko;

  @override
  void initState() {
    super.initState();
    for (final model in widget.models) {
      model.isInstalled().then((value) {
        if (mounted) setState(() => _installed[model.id] = value);
      });
    }
  }

  Future<void> _run(LocalModelEntry model, {required bool install}) async {
    setState(() {
      _busyId = model.id;
      _progress = null;
      _error = null;
    });
    try {
      if (install) {
        await model.download((p) {
          if (mounted) setState(() => _progress = p);
        });
      } else {
        await model.delete();
      }
      final installed = await model.isInstalled();
      if (mounted) setState(() => _installed[model.id] = installed);
    } catch (e) {
      if (mounted) {
        setState(() => _error = install
            ? _t('${model.title} 다운로드에 실패했습니다: $e',
                'Could not download ${model.title}: $e')
            : _t('${model.title} 삭제에 실패했습니다: $e',
                'Could not remove ${model.title}: $e'));
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final busy = _busyId != null;

    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: Text(_t('로컬 모델 관리', 'Local models')),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _t('기기 안에서 전사할 때 쓰는 모델입니다. 어떤 엔진으로 전사할지는 '
                      '설정의 "전사 방식과 녹음 언어"에서 고릅니다.',
                      'Models used for on-device transcription. Choose the engine '
                      'in "Transcription and audio language".'),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.error)),
                ],
                const SizedBox(height: 8),
                for (final model in widget.models)
                  _row(context, model, busy),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.of(context).pop(),
            child: Text(_t('닫기', 'Close')),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, LocalModelEntry model, bool busy) {
    final installed = _installed[model.id];
    final working = _busyId == model.id;

    return Column(
      key: ValueKey('local-model-${model.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(installed == true
              ? Icons.check_circle_outline_rounded
              : Icons.download_for_offline_outlined),
          title: Text(model.title),
          subtitle: Text(installed == true
              ? _t('설치됨 · ${model.subtitle}', 'Installed · ${model.subtitle}')
              : model.subtitle),
          trailing: installed == null
              ? null
              : installed
                  ? OutlinedButton(
                      onPressed:
                          busy ? null : () => _run(model, install: false),
                      child: Text(_t('삭제', 'Remove')),
                    )
                  : FilledButton(
                      onPressed:
                          busy ? null : () => _run(model, install: true),
                      child: Text(_t('다운로드', 'Download')),
                    ),
        ),
        if (working) LinearProgressIndicator(value: _progress),
      ],
    );
  }
}
