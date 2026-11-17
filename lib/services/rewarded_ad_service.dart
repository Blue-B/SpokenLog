import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'cloud_config.dart';

/// Shows an AdMob rewarded ad. The reward itself is granted by the server
/// from AdMob's signed callback, keyed by [userId]; the app only shows the ad.
class RewardedAdService {
  RewardedAdService({CloudConfig? config}) : _config = config ?? CloudConfig.current;

  final CloudConfig _config;
  bool _initialized = false;

  /// Returns true when the user watched to the reward point.
  Future<bool> show({required String userId}) async {
    if (!_config.supportsAds) return false;
    if (!_initialized) {
      await MobileAds.instance.initialize();
      _initialized = true;
    }

    final loaded = Completer<RewardedAd?>();
    await RewardedAd.load(
      adUnitId: _config.rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: loaded.complete,
        onAdFailedToLoad: (_) => loaded.complete(null),
      ),
    );
    final ad = await loaded.future;
    if (ad == null) return false;

    final closed = Completer<void>();
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!closed.isCompleted) closed.complete();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        if (!closed.isCompleted) closed.complete();
      },
    );
    await ad.setServerSideOptions(ServerSideVerificationOptions(userId: userId));
    await ad.show(onUserEarnedReward: (_, _) => earned = true);
    await closed.future;
    return earned;
  }
}
