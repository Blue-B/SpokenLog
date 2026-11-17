import 'dart:io';

/// Build-time settings for SpokenLog cloud, passed with --dart-define.
///
/// Builds without SPOKENLOG_CLOUD_URL (e.g. from source) have no SpokenLog
/// cloud: on-device engines and your own Groq/Cloudflare keys still work.
class CloudConfig {
  const CloudConfig({
    required this.serverUrl,
    required this.androidServerClientId,
    required this.desktopClientId,
    required this.desktopClientSecret,
    required this.rewardedAdUnitId,
  });

  static const fromEnvironment = CloudConfig(
    serverUrl: String.fromEnvironment('SPOKENLOG_CLOUD_URL'),
    // Web OAuth client: the audience of ID tokens issued on Android.
    androidServerClientId: String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID'),
    // Desktop OAuth client; Google treats its secret as non-confidential.
    desktopClientId: String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_ID'),
    desktopClientSecret: String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_SECRET'),
    // Defaults to Google's documented test rewarded unit.
    rewardedAdUnitId: String.fromEnvironment(
      'ADMOB_REWARDED_UNIT_ID',
      defaultValue: 'ca-app-pub-3940256099942544/5224354917',
    ),
  );

  /// Tests replace this; production reads [fromEnvironment].
  static CloudConfig current = fromEnvironment;

  final String serverUrl;
  final String androidServerClientId;
  final String desktopClientId;
  final String desktopClientSecret;
  final String rewardedAdUnitId;

  /// iOS is left out until its sign-in and ad setup exist.
  bool get isAvailable {
    if (serverUrl.isEmpty) return false;
    if (Platform.isAndroid) return androidServerClientId.isNotEmpty;
    if (Platform.isWindows || Platform.isMacOS) return desktopClientId.isNotEmpty;
    return false;
  }

  /// Rewarded ads exist only in the mobile SDK.
  bool get supportsAds => Platform.isAndroid;
}
