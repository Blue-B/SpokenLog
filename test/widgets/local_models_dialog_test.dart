import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_transcriber/widgets/local_models_dialog.dart';

void main() {
  testWidgets('local models dialog downloads and removes without engine choice',
      (tester) async {
    var installed = false;
    await tester.pumpWidget(MaterialApp(
      home: LocalModelsDialog(models: [
        LocalModelEntry(
          id: 'sensevoice',
          title: 'SenseVoice',
          subtitle: '약 239MB',
          isInstalled: () async => installed,
          download: (onProgress) async {
            onProgress(1);
            installed = true;
          },
          delete: () async => installed = false,
        ),
      ]),
    ));
    await tester.pumpAndSettle();

    expect(find.text('로컬 모델 관리'), findsOneWidget);
    expect(find.text('온라인으로 처리'), findsNothing);

    await tester.tap(find.text('다운로드'));
    await tester.pumpAndSettle();
    expect(installed, isTrue);
    expect(find.text('설치됨 · 약 239MB'), findsOneWidget);

    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    expect(installed, isFalse);
    expect(find.text('다운로드'), findsOneWidget);
  });
}
