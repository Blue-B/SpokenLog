import 'package:flutter/material.dart';

/// Keeps credential validation and storage failures above the recording sheet.
class CloudCredentialsDialog extends StatefulWidget {
  const CloudCredentialsDialog({
    super.key,
    required this.providerName,
    required this.initialKey,
    required this.onSave,
    this.initialAccountId = '',
    this.needsAccountId = false,
    this.resumeTranscription = false,
    this.useEnglish = false,
  });

  final String providerName;
  final String initialKey;
  final String initialAccountId;
  final bool needsAccountId;
  final bool resumeTranscription;
  final bool useEnglish;
  final Future<void> Function(String key, String accountId) onSave;

  @override
  State<CloudCredentialsDialog> createState() => _CloudCredentialsDialogState();
}

class _CloudCredentialsDialogState extends State<CloudCredentialsDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _keyController = TextEditingController(text: widget.initialKey);
  late final _accountController =
      TextEditingController(text: widget.initialAccountId);
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  String _t(String ko, String en) => widget.useEnglish ? en : ko;

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        _keyController.text.trim(),
        _accountController.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      // Do not expose platform exceptions that might contain credentials.
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _t(
          '인증 정보를 저장하지 못했습니다. 다시 시도해 주세요.',
          'Could not save your credentials. Please try again.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text('${widget.providerName} ${_t('연결 설정', 'connection')}'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(widget.resumeTranscription
                      ? _t(
                          '전사하려면 인증 정보가 필요합니다. 저장 후 이 녹음을 선택한 서비스로 전송해 전사합니다.',
                          'Credentials are required. After saving, this recording will be sent to the selected service for transcription.',
                        )
                      : _t(
                          '인증 정보는 기기의 보안 저장소에 저장합니다. 녹음은 전사 버튼을 누를 때만 전송합니다.',
                          'Credentials are stored in secure device storage. Audio is sent only when you request transcription.',
                        )),
                  const SizedBox(height: 18),
                  if (widget.needsAccountId) ...[
                    TextFormField(
                      key: const ValueKey('cloud-account-id'),
                      controller: _accountController,
                      enabled: !_saving,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'Cloudflare Account ID',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      validator: (value) => value == null || value.trim().isEmpty
                          ? _t('Account ID를 입력해 주세요.', 'Enter an Account ID.')
                          : null,
                    ),
                    const SizedBox(height: 14),
                  ],
                  TextFormField(
                    key: const ValueKey('cloud-api-key'),
                    controller: _keyController,
                    enabled: !_saving,
                    obscureText: _obscure,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: widget.needsAccountId
                          ? 'Cloudflare API Token'
                          : '${widget.providerName} API Key',
                      hintText: widget.needsAccountId ? null : 'gsk_...',
                      prefixIcon: const Icon(Icons.key_outlined),
                      suffixIcon: IconButton(
                        tooltip: _obscure
                            ? _t('API 키 표시', 'Show API key')
                            : _t('API 키 숨기기', 'Hide API key'),
                        onPressed: _saving
                            ? null
                            : () => setState(() => _obscure = !_obscure),
                        icon: Icon(_obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                      ),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? _t('API 키를 입력해 주세요.', 'Enter an API key.')
                        : null,
                    onFieldSubmitted: (_) => _save(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            child: Text(_t('취소', 'Cancel')),
          ),
          FilledButton(
            key: const ValueKey('save-cloud-credentials'),
            onPressed: _saving ? null : _save,
            child: Text(_saving
                ? _t('저장 중…', 'Saving…')
                : widget.resumeTranscription
                    ? _t('저장 후 전사', 'Save and transcribe')
                    : _t('저장', 'Save')),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _keyController.dispose();
    _accountController.dispose();
    super.dispose();
  }
}
