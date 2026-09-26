import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Public plan guidance, never a claim about the user's remaining balance.
class CloudConnectionHelp extends StatelessWidget {
  const CloudConnectionHelp({
    super.key,
    required this.cloudflare,
    this.useEnglish = false,
  });

  final bool cloudflare;
  final bool useEnglish;

  String _t(String ko, String en) => useEnglish ? en : ko;

  Future<void> _open(BuildContext context, String url) async {
    try {
      if (await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {
      // Offer a copyable URL when no browser/plugin is available.
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('브라우저에서 열어 주세요', 'Open in your browser')),
        content: SelectableText(url),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: Text(_t('링크 복사', 'Copy link')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyUrl = cloudflare
        ? 'https://dash.cloudflare.com/?to=/:account/ai/workers-ai'
        : 'https://console.groq.com/keys';
    final limitsUrl = cloudflare
        ? 'https://developers.cloudflare.com/workers-ai/platform/pricing/'
        : 'https://console.groq.com/settings/limits';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          cloudflare
              ? _t('무료: 하루 약 214분*', 'Free: about 214 audio minutes/day*')
              : _t(
                  '무료 기본 한도: 하루 8시간, 시간당 2시간*',
                  'Free baseline: 8 audio hours/day, 2 hours/hour*',
                ),
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        Text(
          _t(
            '*실제 잔여량이 아닙니다. 계정과 정책에 따라 달라집니다.',
            '*Not your remaining balance. Account limits and policies may differ.',
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Wrap(
          spacing: 4,
          children: [
            TextButton.icon(
              onPressed: () => _open(context, keyUrl),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: Text(
                _t(
                  cloudflare ? '토큰 발급' : 'API 키 발급',
                  cloudflare ? 'Get token' : 'Get API key',
                ),
              ),
            ),
            TextButton(
              onPressed: () => _open(context, limitsUrl),
              child: Text(
                _t(
                  cloudflare ? '공식 한도' : '내 한도 확인',
                  cloudflare ? 'Official limits' : 'My limits',
                ),
              ),
            ),
          ],
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(
            _t('발급 방법과 한도 상세', 'Setup and limit details'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                cloudflare
                    ? _t(
                        'Workers AI → Use REST API에서 토큰을 만들고 Account ID도 복사하세요. '
                            '토큰에는 Workers AI Read/Edit 권한이 필요합니다.\n'
                            '하루 10,000 Neurons를 무료로 제공합니다. 약 214분은 Whisper Turbo만 '
                            '사용할 때의 계산값이며 다른 Workers AI 사용량과 공유됩니다. '
                            '매일 UTC 00:00에 초기화됩니다. 유료 요금제에서는 초과 사용에 비용이 발생할 수 있습니다.',
                        'In Workers AI → Use REST API, create a token and copy the Account ID. '
                            'The token needs Workers AI Read/Edit permissions.\n'
                            '10,000 free Neurons/day: about 214 minutes using only Whisper Turbo. '
                            'Shared with other Workers AI usage; resets at 00:00 UTC. Paid plans may charge for overages.',
                      )
                    : _t(
                        'Groq Console의 API Keys에서 새 키를 만들고 복사하세요.\n'
                            'Whisper 기본 한도는 분당 20회, 하루 2,000회 요청이며 음성 시간 한도도 함께 적용됩니다. '
                            '조직 전체에서 공유하며 계정별 정확한 한도는 Limits에서 확인하세요.',
                        'Create and copy a key in Groq Console → API Keys.\n'
                            'Whisper baseline: 20 requests/minute and 2,000/day, alongside audio-duration limits. '
                            'Shared across your organization; check Limits for your exact allocation.',
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
