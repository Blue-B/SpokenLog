import 'package:flutter/material.dart';

import '../services/spokenlog_cloud_service.dart';

/// Sign-in state, remaining cloud time and the rewarded-ad button for
/// SpokenLog cloud.
class CloudAccountPanel extends StatefulWidget {
  const CloudAccountPanel({
    super.key,
    required this.signIn,
    required this.loadAccount,
    required this.signOut,
    this.watchAd,
    this.useEnglish = false,
  });

  /// Returns the signed-in email, or null. [interactive] may show Google UI.
  final Future<String?> Function({required bool interactive}) signIn;
  final Future<CloudAccount> Function() loadAccount;
  final Future<void> Function() signOut;

  /// Shows a rewarded ad and returns the refreshed account; null on desktop.
  final Future<CloudAccount?> Function()? watchAd;
  final bool useEnglish;

  @override
  State<CloudAccountPanel> createState() => _CloudAccountPanelState();
}

class _CloudAccountPanelState extends State<CloudAccountPanel> {
  String? _email;
  CloudAccount? _account;
  bool _busy = true;
  String? _error;

  String _t(String ko, String en) => widget.useEnglish ? en : ko;

  @override
  void initState() {
    super.initState();
    _run(() => _refresh(interactive: false));
  }

  Future<void> _refresh({required bool interactive}) async {
    _email = await widget.signIn(interactive: interactive);
    _account = _email == null ? null : await widget.loadAccount();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      _error = '$e';
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
    final account = _account;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (!_busy && _email == null) ...[
            Text(_t('Google 계정으로 로그인하면 바로 쓸 수 있습니다. API 키는 필요 없습니다.',
                'Sign in with Google to start. No API key needed.')),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                key: const ValueKey('cloud-sign-in'),
                onPressed: () => _run(() => _refresh(interactive: true)),
                icon: const Icon(Icons.login_rounded),
                label: Text(_t('Google로 로그인', 'Sign in with Google')),
              ),
            ),
          ],
          if (!_busy && _email != null && account != null) ...[
            Row(children: [
              Expanded(child: Text(_email!, style: small)),
              TextButton(
                onPressed: () => _run(() async {
                  await widget.signOut();
                  _email = null;
                  _account = null;
                }),
                child: Text(_t('로그아웃', 'Sign out')),
              ),
            ]),
            Text(
              _t('남은 클라우드 시간 ${_minutes(account.creditSeconds)}',
                  'Cloud time left: ${_minutes(account.creditSeconds)}'),
              key: const ValueKey('cloud-credits'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (widget.watchAd != null)
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.tonalIcon(
                    key: const ValueKey('cloud-watch-ad'),
                    onPressed: account.canWatchAd
                        ? () => _run(() async {
                              _account = await widget.watchAd!() ?? _account;
                            })
                        : null,
                    icon: const Icon(Icons.ondemand_video_rounded),
                    label: Text(_t('광고 보고 ${_minutes(account.adRewardSeconds)} 받기',
                        'Watch an ad for ${_minutes(account.adRewardSeconds)}')),
                  ),
                  Text(_t('오늘 ${account.adsToday}/${account.adsDailyLimit}회',
                      'Today ${account.adsToday}/${account.adsDailyLimit}'), style: small),
                ],
              )
            else
              Text(
                _t('PC에서는 광고를 볼 수 없습니다. 폰 앱에서 같은 Google 계정으로 광고를 보고 받은 시간을 여기서도 쓸 수 있습니다.',
                    'Ads are not available on desktop. Time earned from ads in the phone app with the same Google account works here too.'),
                style: small,
              ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: small?.copyWith(color: scheme.error)),
          ],
          const SizedBox(height: 8),
          Text(
            _t('녹음은 전사를 위해 SpokenLog 서버와 처리 업체로 전송되고, 처리 후 저장하지 않습니다.',
                'Audio is sent to the SpokenLog server and its processors for transcription and is not kept.'),
            style: small,
          ),
        ],
      ),
    );
  }

  String _minutes(int seconds) {
    final minutes = (seconds / 60).floor();
    return widget.useEnglish ? '$minutes min' : '$minutes분';
  }
}
