import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_transcriber/widgets/drag_selection_list.dart';

void main() {
  testWidgets(
    'hold, drag, reverse and deselect a range without losing prior selection',
    (tester) async {
      var selected = <String>{'4'};
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => SizedBox(
              height: 400,
              child: DragSelectionList(
                ids: List.generate(5, (i) => '$i'),
                selected: selected,
                onSelectionChanged: (ids) => setState(() => selected = ids),
                itemBuilder: (_, i) => SizedBox(
                  key: ValueKey('row-$i'),
                  height: 70,
                  child: Text('$i'),
                ),
              ),
            ),
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('row-0'))),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(selected, {'0', '4'});
      await gesture.moveTo(
        tester.getCenter(find.byKey(const ValueKey('row-2'))),
      );
      await tester.pump();
      expect(selected, {'0', '1', '2', '4'});
      await gesture.moveTo(
        tester.getCenter(find.byKey(const ValueKey('row-1'))),
      );
      await tester.pump();
      expect(selected, {'0', '1', '4'});
      await gesture.up();
      await tester.pump();
      final remove = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('row-0'))),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await remove.moveTo(
        tester.getCenter(find.byKey(const ValueKey('row-1'))),
      );
      await tester.pump();
      await remove.up();
      expect(selected, {'4'});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ordinary scrolling does not select; holding near edge scrolls and extends range',
    (tester) async {
      var selected = <String>{};
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              height: 250,
              child: StatefulBuilder(
                builder: (context, setState) => DragSelectionList(
                  ids: List.generate(30, (i) => '$i'),
                  selected: selected,
                  onSelectionChanged: (ids) => setState(() => selected = ids),
                  itemBuilder: (_, i) => SizedBox(
                    key: ValueKey('row-$i'),
                    height: 70,
                    child: Text('$i'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.drag(find.byType(DragSelectionList), const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(selected, isEmpty);
      final row = find.byKey(const ValueKey('row-2'));
      final hold = await tester.startGesture(tester.getCenter(row));
      await tester.pump(const Duration(milliseconds: 600));
      final listRect = tester.getRect(find.byType(DragSelectionList));
      await hold.moveTo(Offset(listRect.center.dx, listRect.bottom - 5));
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 65));
      }
      expect(selected.length, greaterThan(4));
      await hold.up();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );
}
