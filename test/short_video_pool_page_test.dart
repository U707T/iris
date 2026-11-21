import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/file.dart';
import 'package:iris/pages/player/short_video/short_video_feed_widgets.dart';
import 'package:iris/pages/player/short_video/short_video_pool.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class _State extends Fake implements PlayerState {
  @override
  int? get width => 1920;
  @override
  int? get height => 1080;
  @override
  bool get playing => false;
}

class _Streams extends Fake implements PlayerStream {
  @override
  Stream<int?> get width => const Stream.empty();
  @override
  Stream<int?> get height => const Stream.empty();
  @override
  Stream<bool> get playing => const Stream.empty();
}

class _Player extends Fake implements Player {
  @override
  PlayerState get state => _State();
  @override
  PlayerStream get stream => _Streams();
}

class _Controller extends Fake implements VideoController {
  @override
  final Player player = _Player();
  @override
  final notifier = ValueNotifier<PlatformVideoController?>(null);
}

const _a = FileItem(name: 'a.mp4', uri: '/a.mp4');
const _b = FileItem(name: 'b.mp4', uri: '/b.mp4');
const _item = PlayQueueItem(file: _b, index: 8);

Future<void> _pump(WidgetTester tester, ShortVideoSlot? slot) =>
    tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 360,
          height: 640,
          child: ShortVideoPoolPage(slot: slot, item: _item, feedIndex: 1),
        ),
      ),
    );

// This direct child paints after the renderer; do not count Video's own fill.
Finder _cover() => find.descendant(
  of: find.byType(ShortVideoPoolPage),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Positioned &&
        widget.child is ColoredBox &&
        (widget.child as ColoredBox).color == const Color(0xFF000000),
  ),
);

void main() {
  testWidgets('recycled media stays covered without remounting its renderer', (
    tester,
  ) async {
    final controller = _Controller();
    final slot =
        ShortVideoSlot(player: controller.player, controller: controller)
          ..feedIndex = 1
          ..loadedFile = _b
          ..initializing = true
          ..pendingOpen = true;
    await _pump(tester, slot);
    expect(find.byType(Video), findsOneWidget);
    expect(_cover(), findsOneWidget);
    final renderer = tester.element(find.byType(Video));

    slot.pendingOpen = false;
    await _pump(tester, slot);
    expect(
      _cover(),
      findsOneWidget,
      reason: 'open started is not load completion',
    );
    expect(tester.element(find.byType(Video)), same(renderer));

    slot.initializing = false;
    await _pump(tester, slot);
    expect(_cover(), findsNothing);
    expect(tester.element(find.byType(Video)), same(renderer));

    slot.error = 'failed to decode';
    await _pump(tester, slot);
    expect(_cover(), findsOneWidget);
    expect(tester.element(find.byType(Video)), same(renderer));
    await tester.pumpWidget(const SizedBox.shrink());
    controller.notifier.dispose();
  });

  testWidgets(
    'wrong file, wrong page and absent slot never expose another video',
    (tester) async {
      final controller = _Controller();
      final slot =
          ShortVideoSlot(player: controller.player, controller: controller)
            ..feedIndex = 1
            ..loadedFile = _a;
      await _pump(tester, slot);
      expect(_cover(), findsOneWidget);
      slot.loadedFile = _b;
      slot.feedIndex = 0;
      await _pump(tester, slot);
      expect(_cover(), findsOneWidget);
      slot.feedIndex = 1;
      await _pump(tester, slot);
      expect(_cover(), findsNothing);
      await _pump(tester, null);
      expect(find.byType(Video), findsNothing);
      expect(
        find.byType(ShortVideoFeedVideo),
        findsNothing,
        reason: 'a pool page must not borrow the active player as a fallback',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      controller.notifier.dispose();
    },
  );
}
