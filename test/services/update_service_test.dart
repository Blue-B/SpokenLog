import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:voice_transcriber/services/update_service.dart';

Map<String, Object?> release(String tag, {bool withSums = true}) => {
      'tag_name': tag,
      'draft': false,
      'prerelease': false,
      'assets': [
        {
          'name': 'SpokenLog-Android.apk',
          'size': 5,
          'browser_download_url': 'https://example.test/SpokenLog-Android.apk',
        },
        if (withSums)
          {
            'name': 'SHA256SUMS.txt',
            'size': 1,
            'browser_download_url': 'https://example.test/SHA256SUMS.txt',
          },
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('compares versions number by number', () {
    expect(UpdateService.isNewer('0.2.3', '0.2.2'), isTrue);
    expect(UpdateService.isNewer('0.2.10', '0.2.9'), isTrue);
    expect(UpdateService.isNewer('1.0.0', '0.9.9'), isTrue);
    expect(UpdateService.isNewer('0.2.2', '0.2.2'), isFalse);
    expect(UpdateService.isNewer('0.2.1', '0.2.2'), isFalse);
    expect(UpdateService.isNewer('garbage', '0.2.2'), isFalse);
  });

  test('offers only a newer release that has the package and checksums', () {
    const apk = 'SpokenLog-Android.apk';
    final update = UpdateService.parseRelease(release('v0.2.3'), '0.2.2', apk);
    expect(update?.version, '0.2.3');
    expect(update?.downloadUrl.toString(), 'https://example.test/SpokenLog-Android.apk');

    expect(UpdateService.parseRelease(release('v0.2.2'), '0.2.2', apk), isNull);
    expect(UpdateService.parseRelease(release('v0.2.3', withSums: false), '0.2.2', apk), isNull);
    expect(UpdateService.parseRelease(release('v0.2.3'), '0.2.2', 'Other.exe'), isNull);
    expect(UpdateService.parseRelease({...release('v0.2.3'), 'draft': true}, '0.2.2', apk), isNull);
  });

  test('reads the hash for one file from SHA256SUMS.txt', () {
    final a = 'a' * 64, b = 'B' * 64;
    final sums = '$a  SpokenLog-Android.apk\n$b *SpokenLog-Windows-x64-Setup.exe\n';
    expect(UpdateService.expectedHash(sums, 'SpokenLog-Android.apk'), a);
    expect(UpdateService.expectedHash(sums, 'SpokenLog-Windows-x64-Setup.exe'), 'b' * 64);
    expect(UpdateService.expectedHash(sums, 'missing.zip'), isNull);
  });

  group('download', () {
    late Directory temp;
    setUp(() {
      temp = Directory.systemTemp.createTempSync('spokenlog_update_test');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => temp.path,
      );
    });
    tearDown(() => temp.deleteSync(recursive: true));

    UpdateService service(List<int> body, String hash) => UpdateService(
          client: MockClient((request) async => request.url.path.endsWith('SHA256SUMS.txt')
              ? http.Response('$hash  SpokenLog-Android.apk\n', 200)
              : http.Response.bytes(body, 200)),
        );

    final update = UpdateService.parseRelease(release('v9.0.0'), '0.2.2', 'SpokenLog-Android.apk')!;
    final body = utf8.encode('hello');

    test('keeps a package whose checksum matches', () async {
      final progress = <double>[];
      final file = await service(body, sha256.convert(body).toString())
          .download(update, onProgress: progress.add);
      expect(await file.readAsBytes(), body);
      expect(progress.last, 1.0);
    });

    test('rejects and deletes a package whose checksum differs', () async {
      await expectLater(service(body, '0' * 64).download(update), throwsStateError);
      expect(File('${temp.path}/spokenlog_updates/SpokenLog-Android.apk').existsSync(), isFalse);
    });

    test('reuses a verified package instead of downloading it again', () async {
      final hash = sha256.convert(body).toString();
      await service(body, hash).download(update);
      var downloads = 0;
      final again = UpdateService(
        client: MockClient((request) async {
          if (request.url.path.endsWith('SHA256SUMS.txt')) {
            return http.Response('$hash  SpokenLog-Android.apk\n', 200);
          }
          downloads++;
          return http.Response.bytes(body, 200);
        }),
      );
      expect(await (await again.download(update)).readAsBytes(), body);
      expect(downloads, 0);
    });
  });
}
