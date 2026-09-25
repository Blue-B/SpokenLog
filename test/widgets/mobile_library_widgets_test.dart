import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_transcriber/widgets/mobile_library_widgets.dart';

/// Wraps [child] in a phone-sized surface so overflow at narrow widths and
/// large text scales is surfaced as a test failure.
Widget _phone({
  required Widget child,
  required double width,
  double height = 720,
  double textScale = 1.0,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: height,
            child: child,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('MobileLibraryScopeBar', () {
    const tabs = [
      MobileScopeTab(
        scope: 'all',
        label: '전체',
        icon: Icons.folder_open_rounded,
        count: 12,
      ),
      MobileScopeTab(
        scope: 'favorites',
        label: '즐겨찾기',
        icon: Icons.star_outline_rounded,
        count: 3,
      ),
      MobileScopeTab(
        scope: 'collections',
        label: '보관함',
        icon: Icons.folder_copy_outlined,
        count: 7,
      ),
      MobileScopeTab(
        scope: 'trash',
        label: '휴지통',
        icon: Icons.delete_outline_rounded,
        count: 1,
      ),
    ];

    for (final width in const [320.0, 390.0]) {
      testWidgets('shows every fixed scope at ${width.toInt()}px',
          (tester) async {
        String? tapped;
        await tester.pumpWidget(
          _phone(
            width: width,
            child: MobileLibraryScopeBar(
              tabs: tabs,
              selectedScope: 'all',
              onScopeSelected: (scope) => tapped = scope,
            ),
          ),
        );

        // All four scopes are visible without a horizontal scroll view.
        expect(find.text('전체'), findsOneWidget);
        expect(find.text('즐겨찾기'), findsOneWidget);
        expect(find.text('보관함'), findsOneWidget);
        expect(find.text('휴지통'), findsOneWidget);
        expect(find.byType(SingleChildScrollView), findsNothing);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('휴지통'));
        expect(tapped, 'trash');
      });
    }

    testWidgets('survives a 1.6x text scale at 320px', (tester) async {
      await tester.pumpWidget(
        _phone(
          width: 320,
          textScale: 1.6,
          child: MobileLibraryScopeBar(
            tabs: tabs,
            selectedScope: 'collections',
            onScopeSelected: (_) {},
          ),
        ),
      );

      expect(find.text('보관함'), findsOneWidget);
      expect(find.text('휴지통'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('CollectionBrowserView', () {
    final folders = [
      const CollectionFolderData(
        id: 'c1',
        name: '면접 기록',
        recordingCount: 4,
      ),
      const CollectionFolderData(
        id: 'c2',
        name: '아주 긴 한국어 보관함 이름 테스트',
        recordingCount: 12,
      ),
    ];

    testWidgets('lists folders vertically and reports opens', (tester) async {
      String? opened;
      await tester.pumpWidget(
        _phone(
          width: 320,
          child: CollectionBrowserView(
            collections: folders,
            title: '보관함',
            subtitle: '보관함 2개',
            createLabel: '새 보관함',
            backLabel: '보관함 목록',
            renameLabel: '이름 변경',
            deleteLabel: '보관함 삭제',
            menuTooltip: '보관함 메뉴',
            emptyTitle: '아직 보관함이 없습니다.',
            emptyBody: '녹음을 주제별로 정리하려면 보관함을 만들어 보세요.',
            recordingCountLabel: (count) => '$count개',
            onCreate: () {},
            onBack: () {},
            onOpen: (id) => opened = id,
            onRename: (_) {},
            onDelete: (_) {},
          ),
        ),
      );

      expect(find.text('아주 긴 한국어 보관함 이름 테스트'), findsOneWidget);
      expect(find.text('4개'), findsOneWidget);
      expect(find.byType(CollectionFolderTile), findsNWidgets(2));
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('면접 기록'));
      expect(opened, 'c1');
    });

    testWidgets('opens a folder with a clear back path', (tester) async {
      var backCount = 0;
      await tester.pumpWidget(
        _phone(
          width: 390,
          child: CollectionBrowserView(
            collections: folders,
            title: '보관함',
            subtitle: '보관함 2개',
            createLabel: '새 보관함',
            backLabel: '보관함 목록',
            renameLabel: '이름 변경',
            deleteLabel: '보관함 삭제',
            menuTooltip: '보관함 메뉴',
            emptyTitle: '아직 보관함이 없습니다.',
            emptyBody: '녹음을 주제별로 정리하려면 보관함을 만들어 보세요.',
            recordingCountLabel: (count) => '$count개',
            openCollectionId: 'c1',
            openCollectionName: '면접 기록',
            openCollectionSummary: '4개 · 12:30',
            openCollectionBody: const Center(child: Text('recording list')),
            onCreate: () {},
            onBack: () => backCount++,
            onOpen: (_) {},
            onRename: (_) {},
            onDelete: (_) {},
          ),
        ),
      );

      // The back affordance and folder name are shown while inside a folder.
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      expect(find.text('면접 기록'), findsOneWidget);
      expect(find.text('recording list'), findsOneWidget);
      // The folder grid is replaced by the open folder body.
      expect(find.byType(CollectionFolderTile), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      expect(backCount, 1);
    });

    testWidgets('shows create action and empty state', (tester) async {
      var created = 0;
      await tester.pumpWidget(
        _phone(
          width: 320,
          child: CollectionBrowserView(
            collections: const [],
            title: '보관함',
            subtitle: '녹음을 정리할 폴더를 만들어 보세요.',
            createLabel: '새 보관함',
            backLabel: '보관함 목록',
            renameLabel: '이름 변경',
            deleteLabel: '보관함 삭제',
            menuTooltip: '보관함 메뉴',
            emptyTitle: '아직 보관함이 없습니다.',
            emptyBody: '녹음을 주제별로 정리하려면 보관함을 만들어 보세요.',
            onCreate: () => created++,
            onBack: () {},
            onOpen: (_) {},
            onRename: (_) {},
            onDelete: (_) {},
          ),
        ),
      );

      expect(find.text('아직 보관함이 없습니다.'), findsOneWidget);
      await tester.tap(find.text('새 보관함').first);
      expect(created, 1);
      expect(tester.takeException(), isNull);
    });
  });

  group('CalendarAgendaRecordingTile', () {
    const longTitle = '2026년 9월 팀 주간 회의 녹음 전체 전사본 정리 파일';
    const longPreview =
        '이번 주 회의에서는 모바일 보관함 목록과 캘린더 미리보기 디자인을 '
        '함께 검토했고, 한국어 긴 제목이 잘리지 않도록 아젠다 영역을 넓게 '
        '확보하기로 했습니다. 다음 주까지 각 플랫폼별 테스트를 마무리합니다.';

    for (final width in const [320.0, 390.0]) {
      testWidgets('renders long Korean preview on one line budget at '
          '${width.toInt()}px', (tester) async {
        await tester.pumpWidget(
          _phone(
            width: width,
            child: CalendarAgendaRecordingTile(
              title: longTitle,
              metaLabel: '2026-09-19 14:30 · 12:34',
              preview: longPreview,
              hasTranscript: true,
            ),
          ),
        );

        final preview = tester.widget<Text>(find.text(longPreview));
        expect(preview.maxLines, 4);
        expect(preview.overflow, TextOverflow.ellipsis);

        final title = tester.widget<Text>(find.text(longTitle));
        expect(title.maxLines, 2);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('keeps the 4-line preview at 1.4x text scale', (tester) async {
      await tester.pumpWidget(
        _phone(
          width: 320,
          textScale: 1.4,
          child: CalendarAgendaRecordingTile(
            title: longTitle,
            metaLabel: '2026-09-19 14:30 · 12:34',
            preview: longPreview,
            hasTranscript: true,
          ),
        ),
      );

      expect(find.text(longPreview), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('selected-day agenda title column fits 13+ Korean chars',
        (tester) async {
      // A 13-character Korean title, e.g. a typical meeting recording name.
      const thirteenChars = '주간회의녹음전사본정리하기';
      expect(thirteenChars.runes.length, 13);

      await tester.pumpWidget(
        _phone(
          width: 320,
          child: CalendarAgendaRecordingTile(
            title: thirteenChars,
            metaLabel: '2026-09-19 14:30 · 12:34',
            preview: longPreview,
            hasTranscript: true,
          ),
        ),
      );

      final style = tester
          .widget<Text>(find.text(thirteenChars))
          .style;
      final painter = TextPainter(
        text: TextSpan(text: thirteenChars, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();

      final tileWidth = tester.getSize(find.byType(CalendarAgendaRecordingTile))
          .width;
      // Reserve room for leading icon, outer/inner padding, and the menu.
      const tileChrome = 90.0;
      expect(
        painter.width,
        lessThan(tileWidth - tileChrome),
        reason: '13 Korean characters must fit in the agenda title column',
      );
      expect(painter.didExceedMaxLines, isFalse);
    });
  });

  group('CalendarMonthGridView', () {
    const weekdays = ['일', '월', '화', '수', '목', '금', '토'];

    for (final width in const [320.0, 390.0]) {
      testWidgets('shows compact day cells at ${width.toInt()}px',
          (tester) async {
        await tester.pumpWidget(
          _phone(
            width: width,
            child: SingleChildScrollView(
              child: CalendarMonthGridView(
                year: 2026,
                month: 9,
                weekdays: weekdays,
                selectedDay: 19,
                todayDay: 1,
                itemCounts: const {19: 3},
                onDaySelected: (_) {},
              ),
            ),
          ),
        );

        // Every weekday header is shown; the grid never overflows.
        for (final label in weekdays) {
          expect(find.text(label), findsOneWidget);
        }
        expect(find.byType(GridView), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('reports the selected day', (tester) async {
      int? selected;
      await tester.pumpWidget(
        _phone(
          width: 390,
          child: SingleChildScrollView(
            child: CalendarMonthGridView(
              year: 2026,
              month: 9,
              weekdays: weekdays,
              selectedDay: 1,
              onDaySelected: (day) => selected = day,
            ),
          ),
        ),
      );

      // 2026-09-15 exists in the grid and is tappable.
      expect(find.text('15'), findsOneWidget);
      await tester.tap(find.text('15'));
      expect(selected, 15);
    });

    testWidgets('week view renders a single week row', (tester) async {
      await tester.pumpWidget(
        _phone(
          width: 390,
          child: SingleChildScrollView(
            child: CalendarMonthGridView(
              year: 2026,
              month: 9,
              weekdays: weekdays,
              selectedDay: 19,
              weekOnly: true,
              onDaySelected: (_) {},
            ),
          ),
        ),
      );

      // Week of Sep 13-19: day numbers 13..19 are present, neighbours are not.
      expect(find.text('13'), findsOneWidget);
      expect(find.text('19'), findsOneWidget);
      expect(find.text('12'), findsNothing);
      expect(find.text('20'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
