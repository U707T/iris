import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/pages/player/short_video/short_video_page_sync.dart';

void main() {
  testWidgets('latest reverse navigation cancels previous page animation', (
    tester,
  ) async {
    final controller = PageController();
    final sync = ShortVideoPageSync(controller);
    final commits = <int>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: NotificationListener<ScrollEndNotification>(
          onNotification: (_) {
            if (!sync.isSyncing) commits.add(controller.page!.round());
            return false;
          },
          child: PageView(
            controller: controller,
            children: const [
              SizedBox.expand(),
              SizedBox.expand(),
              SizedBox.expand(),
            ],
          ),
        ),
      ),
    );
    final old = sync.syncTo(1);
    await tester.pump(const Duration(milliseconds: 1));
    expect(controller.page!.round(), 0);
    await sync.syncTo(0);
    await tester.pumpAndSettle();
    await old;
    expect(controller.page, 0);
    expect(commits, isNot(contains(1)));
    await tester.pumpWidget(const SizedBox.shrink());
    sync.dispose();
    controller.dispose();
  });
}
