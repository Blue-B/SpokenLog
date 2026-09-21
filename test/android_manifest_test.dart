import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();

  test('Android declares recording and network permissions', () {
    for (final permission in [
      'INTERNET',
      'RECORD_AUDIO',
      'FOREGROUND_SERVICE',
      'FOREGROUND_SERVICE_MICROPHONE',
    ]) {
      expect(
        manifest,
        contains(
          '<uses-permission android:name="android.permission.$permission"',
        ),
      );
    }
  });

  test('Android registers a private microphone foreground service', () {
    final services = RegExp(r'<service\b[^>]*>')
        .allMatches(manifest)
        .map((match) => match.group(0)!)
        .where(
          (tag) => tag.contains(
            'android:name="com.pravera.flutter_foreground_task.service.ForegroundService"',
          ),
        )
        .toList();

    expect(services, hasLength(1));
    expect(
      services.single,
      contains('android:foregroundServiceType="microphone"'),
    );
    expect(services.single, contains('android:exported="false"'));
  });

  test('Android displays the SpokenLog app name', () {
    expect(manifest, contains('android:label="SpokenLog"'));
  });
}
