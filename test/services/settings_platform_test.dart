import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_transcriber/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('macOS credential storage does not require a provisioning profile', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'read' ? 'en' : null;
    });
    try {
      final settings = SettingsService();
      await settings.setAppLanguage('en');
      expect(await settings.getAppLanguage(), 'en');
      expect(calls.map((c) => c.method), ['write', 'read']);
      for (final call in calls) {
        expect(call.arguments['options']['usesDataProtectionKeychain'], 'false');
      }
    } finally {
      messenger.setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
