// Focused widget tests for the recording-detail sheet and the credential /
// settings dialogs introduced with the mobile recording flow.
//
// These mount the widgets directly so validation, error and lifecycle
// behaviour can be asserted without routing through HomeScreen.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_transcriber/widgets/app_settings_sheet.dart';
import 'package:voice_transcriber/widgets/cloud_credentials_dialog.dart';
import 'package:voice_transcriber/widgets/recording_details_sheet.dart';

Finder _textContaining(String value) => find.byWidgetPredicate(
      (widget) => widget is Text && (widget.data ?? '').contains(value),
    );

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(390, 844),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, inner) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: inner!,
      ),
      home: Scaffold(body: child),
    ),
  );
  await tester.pump();
}

void main() {
  group('CloudCredentialsDialog', () {
    testWidgets('requires a non-empty API key before saving', (tester) async {
      var saved = 0;
      await _pump(
        tester,
        CloudCredentialsDialog(
          providerName: 'Groq',
          initialKey: '',
          onSave: (key, account) async => saved++,
        ),
      );

      await tester.tap(find.byKey(const ValueKey('save-cloud-credentials')));
      await tester.pump();

      expect(find.text('API 키를 입력해 주세요.'), findsOneWidget);
      expect(saved, 0);

      await tester.enterText(
        find.byKey(const ValueKey('cloud-api-key')),
        'gsk_test',
      );
      await tester.tap(find.byKey(const ValueKey('save-cloud-credentials')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(saved, 1);
    });

    testWidgets('Cloudflare needs both an account id and a token',
        (tester) async {
      String? savedKey;
      String? savedAccount;
      await _pump(
        tester,
        CloudCredentialsDialog(
          providerName: 'Cloudflare',
          needsAccountId: true,
          initialKey: '',
          onSave: (key, account) async {
            savedKey = key;
            savedAccount = account;
          },
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('cloud-api-key')),
        'token-value',
      );
      await tester.tap(find.byKey(const ValueKey('save-cloud-credentials')));
      await tester.pump();

      expect(find.text('Account ID를 입력해 주세요.'), findsOneWidget);
      expect(savedKey, isNull);

      await tester.enterText(
        find.byKey(const ValueKey('cloud-account-id')),
        'account-123',
      );
      await tester.tap(find.byKey(const ValueKey('save-cloud-credentials')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(savedKey, 'token-value');
      expect(savedAccount, 'account-123');
    });

    testWidgets('storage failure stays on the dialog with a generic message '
        'and never echoes the secret', (tester) async {
      await _pump(
        tester,
        CloudCredentialsDialog(
          providerName: 'Groq',
          initialKey: '',
          onSave: (key, account) async {
            throw Exception('secure storage exception: $key');
          },
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('cloud-api-key')),
        'sk-do-not-leak',
      );
      await tester.tap(find.byKey(const ValueKey('save-cloud-credentials')));
      await tester.pump();

      expect(
        find.text('인증 정보를 저장하지 못했습니다. 다시 시도해 주세요.'),
        findsOneWidget,
      );
      expect(_textContaining('sk-do-not-leak'), findsNothing);
      expect(_textContaining('secure storage exception'), findsNothing);
      // The dialog is still mounted and editable again.
      expect(find.byType(CloudCredentialsDialog), findsOneWidget);
      expect(
        tester.widget<TextFormField>(
          find.byKey(const ValueKey('cloud-api-key')),
        ).enabled,
        isNot(false),
      );
    });

    testWidgets('the key field is obscured by default and can be revealed',
        (tester) async {
      await _pump(
        tester,
        CloudCredentialsDialog(
          providerName: 'Groq',
          initialKey: '',
          onSave: (key, account) async {},
        ),
      );

      EditableText editable() => tester.widget<EditableText>(
            find.descendant(
              of: find.byKey(const ValueKey('cloud-api-key')),
              matching: find.byType(EditableText),
            ),
          );
      expect(editable().obscureText, isTrue);

      await tester.tap(find.byTooltip('API 키 표시'));
      await tester.pump();
      expect(editable().obscureText, isFalse);
    });

    testWidgets('cancel returns false and leaves the dialog', (tester) async {
      bool? result;
      await _pump(
        tester,
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showDialog<bool>(
                context: context,
                builder: (_) => CloudCredentialsDialog(
                  providerName: 'Groq',
                  initialKey: '',
                  onSave: (key, account) async {},
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(CloudCredentialsDialog), findsOneWidget);

      await tester.tap(find.text('취소'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(CloudCredentialsDialog), findsNothing);
      expect(result, isFalse);
    });

    testWidgets('English copy is used when useEnglish is set', (tester) async {
      await _pump(
        tester,
        CloudCredentialsDialog(
          providerName: 'Groq',
          initialKey: '',
          useEnglish: true,
          resumeTranscription: true,
          onSave: (key, account) async {},
        ),
      );

      await tester.tap(find.byKey(const ValueKey('save-cloud-credentials')));
      await tester.pump();
      expect(find.text('Enter an API key.'), findsOneWidget);
      expect(find.text('Save and transcribe'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('narrow width with large text does not overflow',
        (tester) async {
      await _pump(
        tester,
        CloudCredentialsDialog(
          providerName: 'Cloudflare',
          needsAccountId: true,
          initialKey: '',
          onSave: (key, account) async {},
        ),
        size: const Size(320, 640),
        textScale: 1.8,
      );

      expect(find.byKey(const ValueKey('cloud-api-key')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('disposing while a save is in flight does not throw',
        (tester) async {
      final completer = Completer<void>();
      await _pump(
        tester,
        CloudCredentialsDialog(
          providerName: 'Groq',
          initialKey: 'gsk_existing',
          onSave: (key, account) => completer.future,
        ),
      );

      await tester.tap(find.byKey(const ValueKey('save-cloud-credentials')));
      await tester.pump();

      // Replace the tree before the save future completes.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      expect(tester.takeException(), isNull);

      completer.complete();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('AppSettingsSheet', () {
    Map<String, int> calls() => {
          'groq': 0,
          'cloudflare': 0,
          'models': 0,
          'transcription': 0,
          'language': 0,
          'licenses': 0,
        };

    testWidgets('every entry invokes its callback', (tester) async {
      final counts = calls();
      await _pump(
        tester,
        AppSettingsSheet(
          onGroq: () => counts['groq'] = counts['groq']! + 1,
          onCloudflare: () => counts['cloudflare'] = counts['cloudflare']! + 1,
          onLocalModels: () => counts['models'] = counts['models']! + 1,
          onTranscription: () =>
              counts['transcription'] = counts['transcription']! + 1,
          onDisplayLanguage: () => counts['language'] = counts['language']! + 1,
          onLicenses: () => counts['licenses'] = counts['licenses']! + 1,
        ),
      );

      for (final entry in const {
        'settings-groq': 'groq',
        'settings-cloudflare': 'cloudflare',
        'settings-local-models': 'models',
        'settings-transcription': 'transcription',
        'settings-display-language': 'language',
        'settings-licenses': 'licenses',
      }.entries) {
        await tester.tap(find.byKey(ValueKey(entry.key)));
        await tester.pump();
        expect(counts[entry.value], 1, reason: entry.key);
      }
    });

    testWidgets('localizes labels when useEnglish is set', (tester) async {
      // A tall surface ensures the lazily-built list reaches the last entry.
      await _pump(
        tester,
        AppSettingsSheet(
          useEnglish: true,
          onGroq: () {},
          onCloudflare: () {},
          onLocalModels: () {},
          onTranscription: () {},
          onDisplayLanguage: () {},
        ),
        size: const Size(390, 1600),
      );

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Display language'), findsOneWidget);
      expect(find.text('Local models'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('close button pops its route', (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: ElevatedButton(
            onPressed: () => navigatorKey.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  body: AppSettingsSheet(
                    onGroq: () {},
                    onCloudflare: () {},
                    onLocalModels: () {},
                    onTranscription: () {},
                    onDisplayLanguage: () {},
                  ),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(AppSettingsSheet), findsOneWidget);

      await tester.tap(find.byTooltip('닫기'));
      // No playing timers here, so settling the route transition is safe.
      await tester.pumpAndSettle();
      expect(find.byType(AppSettingsSheet), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('narrow width with large text does not overflow',
        (tester) async {
      await _pump(
        tester,
        AppSettingsSheet(
          onGroq: () {},
          onCloudflare: () {},
          onLocalModels: () {},
          onTranscription: () {},
          onDisplayLanguage: () {},
        ),
        size: const Size(320, 640),
        textScale: 1.8,
      );

      expect(find.byKey(const ValueKey('settings-display-language')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settings-groq')), 200,
        scrollable: find.byType(Scrollable),
      );
      expect(find.byKey(const ValueKey('settings-groq')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('RecordingDetailsSheet', () {
    testWidgets('rebuilds its body when the changes notifier fires',
        (tester) async {
      final changes = ValueNotifier<int>(0);
      addTearDown(changes.dispose);

      await _pump(
        tester,
        RecordingDetailsSheet(
          changes: changes,
          messengerKey: GlobalKey<ScaffoldMessengerState>(),
          builder: (_) => Text('body-${changes.value}'),
        ),
      );

      expect(find.text('body-0'), findsOneWidget);

      changes.value = 1;
      await tester.pump();
      expect(find.text('body-1'), findsOneWidget);
      expect(find.text('body-0'), findsNothing);

      changes.value = 2;
      await tester.pump();
      expect(find.text('body-2'), findsOneWidget);
    });

    testWidgets('uses English close tooltip and pops the route',
        (tester) async {
      final changes = ValueNotifier<int>(0);
      addTearDown(changes.dispose);

      await _pump(
        tester,
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (_) => RecordingDetailsSheet(
                changes: changes,
                messengerKey: GlobalKey<ScaffoldMessengerState>(),
                useEnglish: true,
                builder: (_) => const Text('detail'),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(RecordingDetailsSheet), findsOneWidget);

      await tester.tap(find.byTooltip('Close recording'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(RecordingDetailsSheet), findsNothing);
    });

    testWidgets('disposing the sheet while it listens does not throw',
        (tester) async {
      final changes = ValueNotifier<int>(0);
      addTearDown(changes.dispose);

      await _pump(
        tester,
        RecordingDetailsSheet(
          changes: changes,
          messengerKey: GlobalKey<ScaffoldMessengerState>(),
          builder: (_) => const Text('detail'),
        ),
      );

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      expect(tester.takeException(), isNull);

      // Firing after teardown must not touch the disposed element tree.
      changes.value = 5;
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
