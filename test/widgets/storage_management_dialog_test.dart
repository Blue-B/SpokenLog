import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_transcriber/services/app_storage_service.dart';
import 'package:voice_transcriber/widgets/storage_management_dialog.dart';

Future<void> settleFiles(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'storage keeps everything by default; cancel preserves and confirm deletes only models',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final root = Directory.systemTemp.createTempSync('spokenlog_storage_ui_');
      addTearDown(() => root.delete(recursive: true));
      final docs = Directory('${root.path}/docs');
      final support = Directory('${root.path}/support');
      final audio = File('${docs.path}/recordings/audio.wav');
      final model = File('${support.path}/models/model.onnx');
      audio.createSync(recursive: true);
      model.createSync(recursive: true);
      final storage = AppStorageService(
        documents: () async => docs,
        support: () async => support,
      );
      var settingsCleared = false;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!,
          ),
          home: Scaffold(
            body: StorageManagementDialog(
              storage: storage,
              onClearSettings: () async => settingsCleared = true,
            ),
          ),
        ),
      );
      await settleFiles(tester);
      final button = find.byKey(const ValueKey('delete-selected-storage'));
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      expect(
        find
            .byType(CheckboxListTile)
            .evaluate()
            .every((e) => !(e.widget as CheckboxListTile).value!),
        isTrue,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('storage-models')));
      await tester.tap(find.byKey(const ValueKey('storage-models')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(model.existsSync(), isTrue);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-storage-delete')));
      await settleFiles(tester);
      expect(model.existsSync(), isFalse);
      expect(audio.existsSync(), isTrue);
      expect(settingsCleared, isFalse);
      expect(find.text('선택한 데이터를 삭제했습니다.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'uninstall preserve and cancel are distinct decisions without cleanup',
    (tester) async {
      final root = Directory.systemTemp.createTempSync(
        'spokenlog_uninstall_ui_',
      );
      addTearDown(() => root.delete(recursive: true));
      bool? decision;
      var clearCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StorageManagementDialog(
              storage: AppStorageService(
                documents: () async => root,
                support: () async => root,
              ),
              onClearSettings: () async => clearCalls++,
              onUninstallDecision: (proceed) => decision = proceed,
            ),
          ),
        ),
      );
      await settleFiles(tester);
      await tester.tap(find.text('제거 취소'));
      expect(decision, isFalse);
      await tester.tap(find.text('모두 보존하고 계속'));
      expect(decision, isTrue);
      expect(clearCalls, 0);
    },
  );
}
