import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_transcriber/widgets/cloud_credentials_dialog.dart';

void main() {
  for (final cloudflare in [false, true]) {
    testWidgets(
      'connection shows public limits and usable links before credentials: $cloudflare',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final urls = <String>[];
        const channel = MethodChannel('plugins.flutter.io/url_launcher');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
          call,
        ) async {
          urls.add((call.arguments as Map)['url'] as String);
          return false; // Browser unavailable: the link must still be copyable.
        });
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
              child: Scaffold(
                body: CloudCredentialsDialog(
                  providerName: cloudflare ? 'Cloudflare' : 'Groq',
                  initialKey: '',
                  needsAccountId: cloudflare,
                  onSave: (_, _) async {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining(cloudflare ? '214분' : '하루 8시간'),
          findsOneWidget,
        );
        expect(find.textContaining('실제 잔여량이 아닙니다'), findsOneWidget);
        final link = find.text(cloudflare ? '토큰 발급' : 'API 키 발급');
        await tester.ensureVisible(link);
        await tester.tap(link);
        await tester.pumpAndSettle();
        expect(
          urls.single,
          cloudflare
              ? 'https://dash.cloudflare.com/?to=/:account/ai/workers-ai'
              : 'https://console.groq.com/keys',
        );
        expect(find.text('링크 복사'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
