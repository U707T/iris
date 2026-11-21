import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/pages/player/short_video/short_video_pager.dart';

Future<void> _mount(
  WidgetTester tester, {
  required ValueNotifier<int> index,
  required List<int> commits,
  int itemCount = 20,
  Set<int>? built,
  bool competeWithTap = false,
}) async {
  final pages = ValueListenableBuilder<int>(
    valueListenable: index,
    builder: (_, value, _) => ShortVideoPager(
      currentIndex: value,
      itemCount: itemCount,
      onPageSettled: (page) {
        commits.add(page);
        index.value = page;
      },
      itemBuilder: (_, page) {
        built?.add(page);
        return ColoredBox(key: ValueKey(page), color: Color(0xFF000000 + page));
      },
    ),
  );
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 400,
          height: 600,
          // The production gesture layer competes with the scrollable for taps.
          // A lone vertical drag recognizer wins on pointer down by default.
          child: competeWithTap
              ? GestureDetector(onTap: () {}, child: pages)
              : pages,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

PageController _controller(WidgetTester tester) =>
    tester.widget<PageView>(find.byType(PageView)).controller!;

Future<void> _close(WidgetTester tester, ValueNotifier<int> index) async {
  await tester.pumpWidget(const SizedBox.shrink());
  index.dispose();
}

void main() {
  testWidgets(
    'fling commits once after settling, never at the halfway crossing',
    (tester) async {
      final index = ValueNotifier(0);
      final commits = <int>[];
      await _mount(tester, index: index, commits: commits);
      final controller = _controller(tester);
      await tester.fling(find.byType(PageView), const Offset(0, -340), 1000);
      var observedHalfway = false;
      for (var frame = 0; frame < 12; frame++) {
        await tester.pump(const Duration(milliseconds: 5));
        final page = controller.page!;
        if (page > 0.5 &&
            page < 0.99 &&
            controller.position.isScrollingNotifier.value) {
          observedHalfway = true;
          expect(
            commits,
            isEmpty,
            reason: 'crossing halfway must not replace the native ballistic',
          );
          break;
        }
      }
      expect(observedHalfway, isTrue);
      await tester.pumpAndSettle();
      expect(controller.page, closeTo(1, 0.000001));
      expect(commits, [1]);
      // Echoing the settled page back from the store cannot start another scroll.
      await tester.pumpAndSettle();
      expect(commits, [1]);
      await _close(tester, index);
    },
  );

  testWidgets('a short cancelled drag returns to its page without committing', (
    tester,
  ) async {
    final index = ValueNotifier(1);
    final commits = <int>[];
    await _mount(tester, index: index, commits: commits);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PageView)),
    );
    await gesture.moveBy(const Offset(0, -110));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(_controller(tester).page, closeTo(1, 0.000001));
    expect(commits, isEmpty);
    await _close(tester, index);
  });

  testWidgets('reversing an unsettled swipe never commits its abandoned page', (
    tester,
  ) async {
    final index = ValueNotifier(1);
    final commits = <int>[];
    await _mount(tester, index: index, commits: commits);
    await tester.fling(find.byType(PageView), const Offset(0, -280), 1200);
    await tester.pump(const Duration(milliseconds: 16));
    expect(_controller(tester).position.isScrollingNotifier.value, isTrue);
    expect(commits, isEmpty);
    final reverse = await tester.startGesture(
      tester.getTopLeft(find.byType(PageView)) + const Offset(200, 70),
    );
    await reverse.moveBy(const Offset(0, 330));
    await tester.pump(const Duration(milliseconds: 300));
    await reverse.up();
    await tester.pumpAndSettle();
    expect(_controller(tester).page, closeTo(1, 0.000001));
    expect(commits, isEmpty);
    await _close(tester, index);
  });

  for (final reverse in [false, true]) {
    testWidgets(
      reverse
          ? 'holding after halfway and reversing never commits the abandoned page'
          : 'holding after halfway and releasing commits only after the resumed spring',
      (tester) async {
        final index = ValueNotifier(1);
        final commits = <int>[];
        await _mount(
          tester,
          index: index,
          commits: commits,
          competeWithTap: true,
        );
        final pager = find.byType(PageView);
        final controller = _controller(tester);
        await tester.fling(pager, const Offset(0, -340), 1000);
        for (var frame = 0; frame < 12 && controller.page! <= 1.5; frame++) {
          await tester.pump(const Duration(milliseconds: 5));
        }
        expect(controller.page, allOf(greaterThan(1.5), lessThan(1.95)));
        expect(controller.position.isScrollingNotifier.value, isTrue);
        expect(commits, isEmpty);

        final touch = await tester.startGesture(
          tester.getTopLeft(pager) + const Offset(200, 20),
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(controller.position.isScrollingNotifier.value, isFalse);
        expect(
          commits,
          isEmpty,
          reason: 'a hold is an interruption, not a landing',
        );
        if (reverse) {
          await touch.moveBy(const Offset(0, 25));
          final distance =
              (controller.page! - 1.1) * controller.position.viewportDimension;
          await touch.moveBy(Offset(0, distance));
          await tester.pump(const Duration(milliseconds: 300));
        }
        await touch.up();
        expect(commits, isEmpty);
        await tester.pumpAndSettle();
        expect(controller.page, closeTo(reverse ? 1 : 2, 0.000001));
        expect(commits, reverse ? <int>[] : [2]);
        await _close(tester, index);
      },
    );
  }

  testWidgets('external navigation and a rapid reverse never write back', (
    tester,
  ) async {
    final index = ValueNotifier(0);
    final commits = <int>[];
    await _mount(tester, index: index, commits: commits);
    index.value = 2;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    index.value = 0;
    await tester.pump();
    await tester.pumpAndSettle();
    expect(_controller(tester).page, closeTo(0, 0.000001));
    expect(commits, isEmpty);
    index.value = 3;
    await tester.pumpAndSettle();
    expect(_controller(tester).page, closeTo(3, 0.000001));
    expect(commits, isEmpty);
    await _close(tester, index);
  });

  testWidgets('showing a cached page on screen commits its playback index', (
    tester,
  ) async {
    final index = ValueNotifier(1);
    final commits = <int>[];
    await _mount(tester, index: index, commits: commits);
    final neighbour = find.byKey(const ValueKey(2), skipOffstage: false);
    expect(neighbour, findsOneWidget);
    // Focus and accessibility can move the viewport without a drag.
    tester.renderObject(neighbour).showOnScreen();
    await tester.pumpAndSettle();
    expect(_controller(tester).page, closeTo(2, 0.000001));
    expect(commits, [2]);
    await _close(tester, index);
  });

  testWidgets(
    'implicit scrolling mounts neighbours without building the feed',
    (tester) async {
      final index = ValueNotifier(2);
      final commits = <int>[];
      final built = <int>{};
      await _mount(
        tester,
        index: index,
        commits: commits,
        itemCount: 100,
        built: built,
      );
      expect(built, containsAll([1, 2, 3]));
      expect(built.length, lessThanOrEqualTo(5));
      expect(built, isNot(contains(50)));
      await _close(tester, index);
    },
  );
}
