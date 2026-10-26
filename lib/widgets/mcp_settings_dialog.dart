import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Copy-paste setup for each AI tool, given the local MCP address.
List<(String, String)> mcpClientSnippets(String url) => [
      ('Claude Code', 'claude mcp add -s user --transport http spokenlog $url'),
      ('Codex', 'codex mcp add spokenlog --url $url'),
      ('pi (~/.pi/agent/mcp.json)', '"spokenlog": { "url": "$url" }'),
      (
        'Claude Desktop (claude_desktop_config.json, Node.js)',
        '"spokenlog": { "command": "npx", "args": ["-y", "mcp-remote", "$url"] }',
      ),
    ];

/// Turns the read-only MCP server on or off and shows how to connect.
class McpSettingsDialog extends StatefulWidget {
  const McpSettingsDialog({
    super.key,
    required this.url,
    required this.onToggle,
    required this.onResetToken,
    this.onOpenGuide,
    this.useEnglish = false,
  });

  /// Current address, or null while the server is off.
  final String? url;

  /// Starts or stops the server; returns the new address (null when off).
  final Future<String?> Function(bool enable) onToggle;
  final Future<String> Function() onResetToken;
  final VoidCallback? onOpenGuide;
  final bool useEnglish;

  @override
  State<McpSettingsDialog> createState() => _McpSettingsDialogState();
}

class _McpSettingsDialogState extends State<McpSettingsDialog> {
  late String? _url = widget.url;
  bool _busy = false;
  bool _reveal = false;
  String? _notice;
  bool _noticeIsError = false;

  String _t(String ko, String en) => widget.useEnglish ? en : ko;

  Future<void> _run(Future<String?> Function() action) async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final url = await action();
      if (mounted) setState(() => _url = url);
    } catch (e) {
      if (mounted) {
        setState(() {
          _notice = '$e';
          _noticeIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: scheme.onSurfaceVariant);
    final url = _url;
    final token = url?.split('/').last;

    return AlertDialog(
      title: Text(_t('AI 연결 (MCP)', 'AI connection (MCP)')),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                key: const ValueKey('mcp-enabled'),
                contentPadding: EdgeInsets.zero,
                value: url != null,
                title: Text(_t('AI 도구가 녹음을 읽도록 허용', 'Let AI tools read recordings')),
                subtitle: Text(_t(
                  'Claude Code, Codex, pi 같은 AI 도구가 이 PC의 녹음 목록과 전사를 '
                  '검색하고 읽을 수 있습니다. 읽기만 하며 수정·삭제는 할 수 없습니다. '
                  '앱이 켜져 있는 동안만 동작합니다.',
                  'AI tools such as Claude Code, Codex and pi can search and read '
                  'recordings and transcripts on this computer. Read-only. Works '
                  'while the app is open.',
                )),
                onChanged: _busy ? null : (value) => _run(() => widget.onToggle(value)),
              ),
              Text(
                _t('AI가 읽은 전사는 그 AI 서비스(예: Claude, ChatGPT)로 전송됩니다. '
                    '로컬 LLM을 쓰면 PC 밖으로 나가지 않습니다.',
                    'Transcripts the AI reads are sent to that AI service. With a '
                    'local LLM they stay on this computer.'),
                style: small,
              ),
              if (_notice != null) ...[
                const SizedBox(height: 8),
                Text(_notice!,
                    style: small?.copyWith(
                        color: _noticeIsError ? scheme.error : scheme.primary)),
              ],
              if (url != null && token != null) ...[
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: Text(_t('연결 방법 (복사해서 붙여넣기)', 'Setup (copy and paste)'),
                        style: Theme.of(context).textTheme.titleSmall),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _reveal = !_reveal),
                    child: Text(_reveal ? _t('주소 숨기기', 'Hide address') : _t('주소 보기', 'Show address')),
                  ),
                ]),
                for (final (label, text) in [
                  (_t('주소', 'Address'), url),
                  ...mcpClientSnippets(url),
                ])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(label),
                    subtitle: Text(
                      _reveal ? text : text.replaceAll(token, '••••••'),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                    trailing: IconButton(
                      tooltip: _t('복사', 'Copy'),
                      icon: const Icon(Icons.copy_rounded),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: text));
                        if (!mounted) return;
                        setState(() {
                          _notice = _t('$label 설정을 복사했습니다.', 'Copied $label setup.');
                          _noticeIsError = false;
                        });
                      },
                    ),
                  ),
                Text(
                  _t('주소에 비밀 키가 들어 있습니다. 다른 사람과 공유하지 마세요.',
                      'The address contains a secret key. Do not share it.'),
                  style: small,
                ),
                Wrap(spacing: 8, children: [
                  if (widget.onOpenGuide != null)
                    TextButton.icon(
                      onPressed: widget.onOpenGuide,
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: Text(_t('ChatGPT·Claude 웹 연결 안내', 'ChatGPT / Claude web guide')),
                    ),
                  TextButton.icon(
                    onPressed: _busy ? null : () => _run(widget.onResetToken),
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(_t('주소 새로 만들기 (기존 연결 끊김)', 'New address (disconnects tools)')),
                  ),
                ]),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_t('닫기', 'Close')),
        ),
      ],
    );
  }
}
