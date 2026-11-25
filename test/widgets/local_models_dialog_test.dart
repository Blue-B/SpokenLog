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
    expect(find.text('설치됨'), findsOneWidget);
    expect(find.text('약 239MB'), findsOneWidget);

    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    expect(installed, isFalse);
    expect(find.text('다운로드'), findsOneWidget);
    expect(find.text('설치됨'), findsNothing);
  });

  testWidgets('a narrow phone dialog keeps the description on full-width lines',
      (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const description = '한국어·영어·중국어·일본어·광둥어 · 약 239MB';
    await tester.pumpWidget(MaterialApp(
      home: LocalModelsDialog(models: [
        LocalModelEntry(
          id: 'sensevoice',
          title: 'SenseVoice',
          subtitle: description,
          isInstalled: () async => false,
          download: (_) async {},
          delete: () async {},
        ),
      ]),
    ));
    await tester.pumpAndSettle();

    final text = tester.getRect(find.text(description));
    final button = tester.getRect(find.text('다운로드'));
    expect(button.top, greaterThan(text.bottom)); // button sits below, not beside
    expect(text.height, lessThan(60)); // at most a few lines, not a squeezed column
    expect(tester.takeException(), isNull);
  });
}
