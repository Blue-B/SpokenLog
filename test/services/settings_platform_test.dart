import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_transcriber/models/transcription_provider.dart';
import 'package:voice_transcriber/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('reset deletes only owned keys, never the entire secure store', () async {
    const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    try {
      await SettingsService().clearAppSettings();
      expect(calls, hasLength(17));
      expect(calls.every((call) => call.method == 'delete'), isTrue);
      expect(calls.map((call) => call.arguments['key']), containsAll([
        'groq_api_key', 'cloudflare_api_token', 'cloudflare_account_id',
        'app_language', 'transcription_provider', 'local_whisper_model',
      ]));
    } finally {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });
  test('macOS uses the existing file-based Keychain option', () async {
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

  test('Whisper size is remembered separately and bad values fall back', () async {
    const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final store = <String, String>{};
    messenger.setMockMethodCallHandler(channel, (call) async {
      final key = call.arguments['key'] as String?;
      switch (call.method) {
        case 'write':
          store[key!] = call.arguments['value'] as String;
          return null;
        case 'read':
          return store[key];
        default:
          return null;
      }
    });
    try {
      final settings = SettingsService();
      const whisper = TranscriptionProvider.localWhisper;
      expect(await settings.getModel(whisper), 'whisper-tiny-multilingual-int8');

      await settings.setModel(whisper, 'whisper-base-multilingual-int8');
      expect(await settings.getModel(whisper), 'whisper-base-multilingual-int8');
      // Groq keeps its own choice.
      expect(await settings.getModel(TranscriptionProvider.groq), 'whisper-large-v3');

      store['local_whisper_model'] = 'not-a-model';
      expect(await settings.getModel(whisper), 'whisper-tiny-multilingual-int8');
      await expectLater(
        settings.setModel(whisper, 'whisper-large-v3'),
        throwsArgumentError,
      );
    } finally {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });
}
