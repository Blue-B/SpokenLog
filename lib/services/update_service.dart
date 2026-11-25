import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// A newer GitHub release with a package for this platform.
class AvailableUpdate {
  const AvailableUpdate({
    required this.version,
    required this.assetName,
    required this.downloadUrl,
    required this.sizeBytes,
    required this.checksumsUrl,
  });

  final String version;
  final String assetName;
  final Uri downloadUrl;
  final int sizeBytes;
  final Uri checksumsUrl;
}

/// Checks GitHub releases on launch and installs newer Android/Windows builds.
///
/// The package is verified against the release's SHA256SUMS.txt before it is
/// installed. Android then shows its own install screen; the Windows
/// installer runs silently and starts the new version.
class UpdateService {
  UpdateService({http.Client? client}) : _client = client ?? http.Client();

  static final latestRelease =
      Uri.parse('https://api.github.com/repos/Blue-B/SpokenLog/releases/latest');
  static const _channel = MethodChannel('spokenlog_audio');

  final http.Client _client;

  /// Android, and Windows copies installed by the Setup (a ZIP copy has no
  /// uninstaller next to it and would get a second, installed copy).
  static bool get supported =>
      Platform.isAndroid ||
      (Platform.isWindows &&
          File('${File(Platform.resolvedExecutable).parent.path}\\unins000.exe').existsSync());

  static String? get assetForPlatform => Platform.isAndroid
      ? 'SpokenLog-Android.apk'
      : Platform.isWindows
          ? 'SpokenLog-Windows-x64-Setup.exe'
          : null;

  /// The newer release, or null when up to date, offline or unsupported.
  Future<AvailableUpdate?> check({String? currentVersion, String? asset}) async {
    asset ??= assetForPlatform;
    if (asset == null) return null;
    currentVersion ??= (await PackageInfo.fromPlatform()).version;
    final response = await _client
        .get(latestRelease, headers: {'Accept': 'application/vnd.github+json'})
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return null;
    final update = parseRelease(jsonDecode(response.body), currentVersion, asset);
    if (update == null) {
      // Up to date: the package from the last update is no longer needed.
      try {
        final dir = await _updatesDir();
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {}
    }
    return update;
  }

  /// Our own folder: on Windows the temporary directory is the shared %TEMP%.
  /// Must match packages/spokenlog_audio/.../res/xml/spokenlog_update_paths.xml.
  static Future<Directory> _updatesDir() async => Directory(
      '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}spokenlog_updates');

  static AvailableUpdate? parseRelease(Object? json, String currentVersion, String asset) {
    if (json is! Map || json['draft'] == true || json['prerelease'] == true) return null;
    final version = json['tag_name']?.toString().replaceFirst(RegExp('^v'), '') ?? '';
    if (!isNewer(version, currentVersion)) return null;
    final assets = (json['assets'] as List? ?? const []).whereType<Map>();
    Map? named(String name) => assets.where((a) => a['name'] == name).firstOrNull;
    final package = named(asset);
    final sums = named('SHA256SUMS.txt');
    if (package == null || sums == null) return null;
    return AvailableUpdate(
      version: version,
      assetName: asset,
      downloadUrl: Uri.parse(package['browser_download_url'].toString()),
      sizeBytes: (package['size'] as num?)?.toInt() ?? 0,
      checksumsUrl: Uri.parse(sums['browser_download_url'].toString()),
    );
  }

  /// Compares dotted numbers: 0.2.10 is newer than 0.2.9.
  static bool isNewer(String candidate, String current) {
    List<int> parts(String v) =>
        v.split(RegExp(r'[.+-]')).take(3).map((p) => int.tryParse(p) ?? 0).toList();
    final a = parts(candidate), b = parts(current);
    if (a.length < 3 || a.every((n) => n == 0)) return false;
    while (b.length < 3) {
      b.add(0);
    }
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }

  /// Hash for [asset] in a sha256sum-style file.
  static String? expectedHash(String sums, String asset) {
    for (final line in const LineSplitter().convert(sums)) {
      final match = RegExp(r'^([0-9a-fA-F]{64})\s+\*?(.+)$').firstMatch(line.trim());
      if (match != null && match.group(2) == asset) return match.group(1)!.toLowerCase();
    }
    return null;
  }

  /// Downloads and verifies the package; [onProgress] gets 0..1.
  Future<File> download(AvailableUpdate update, {void Function(double)? onProgress}) async {
    final sums = await _client.get(update.checksumsUrl).timeout(const Duration(seconds: 30));
    final expected = sums.statusCode == 200 ? expectedHash(sums.body, update.assetName) : null;
    if (expected == null) throw StateError('No checksum for ${update.assetName}');

    final dir = await _updatesDir();
    final file = File('${dir.path}${Platform.pathSeparator}${update.assetName}');
    // A package verified earlier (the install screen was cancelled) is reused.
    if (await file.exists() && (await sha256.bind(file.openRead()).first).toString() == expected) {
      onProgress?.call(1);
      return file;
    }
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);

    final response = await _client
        .send(http.Request('GET', update.downloadUrl))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw HttpException('Download failed (HTTP ${response.statusCode})');
    }
    final total = response.contentLength ?? update.sizeBytes;
    final sink = file.openWrite();
    final digest = _DigestSink();
    final hasher = sha256.startChunkedConversion(digest);
    var received = 0;
    try {
      await for (final chunk in response.stream.timeout(const Duration(seconds: 60))) {
        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
    } finally {
      await sink.close();
      hasher.close();
    }
    if (digest.value.toString() != expected) {
      await file.delete();
      throw StateError('The downloaded file did not match its checksum');
    }
    return file;
  }

  /// Android: system install screen. Windows: silent install, then the
  /// installer starts the new version; the caller should quit right after.
  Future<void> install(File package) async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('installApk', {'path': package.path});
    } else if (Platform.isWindows) {
      await Process.start(
        package.path,
        ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS'],
        mode: ProcessStartMode.detached,
      );
    }
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
