import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:iris/pages/player/short_video/short_video_page_sync.dart';
import 'package:iris/utils/logger.dart';

/// A swipe changes playback only after PageView's own settling animation ends.
/// External navigation still animates to its destination without feeding back.
class ShortVideoPager extends StatefulWidget {
  const ShortVideoPager({
    super.key,
    required this.currentIndex,
    required this.itemCount,
    required this.itemBuilder,
    required this.onPageSettled,
  });

  final int currentIndex;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ValueChanged<int> onPageSettled;

  @override
  State<ShortVideoPager> createState() => _ShortVideoPagerState();
}

class _ShortVideoPagerState extends State<ShortVideoPager> {
  late final _controller = PageController(initialPage: widget.currentIndex);
  late final _sync = ShortVideoPageSync(_controller);
  bool _userScrolling = false;

  @override
  void didUpdateWidget(covariant ShortVideoPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentIndex != oldWidget.currentIndex ||
        widget.itemCount != oldWidget.itemCount) {
      _userScrolling = false;
      unawaited(
        _sync.syncTo(widget.currentIndex).catchError((Object error) {
          logger('Short video page sync failed: $error');
        }),
      );
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification &&
        (notification.dragDetails != null || !_sync.isSyncing)) {
      // Implicit scrolling from accessibility or focus also changes the
      // visible page, but has no drag details.
      _userScrolling = true;
    }
    if (notification is ScrollEndNotification) {
      if (!_userScrolling || _sync.isSyncing) return false;
      final page = _controller.page;
      if (page == null) return false;
      final target = page.round();
      // Touching a moving page ends the ballistic activity as Flutter enters
      // a hold. Keep tracking until the drag or the resumed spring settles.
      if ((page - target).abs() >= 0.000001) return false;
      _userScrolling = false;
      if (target >= 0 &&
          target < widget.itemCount &&
          target != widget.currentIndex) {
        widget.onPageSettled(target);
      }
    }
    return false;
  }

  @override
  void dispose() {
    _sync.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          scrollbars: false,
          overscroll: false,
          dragDevices: const {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.stylus,
            PointerDeviceKind.trackpad,
          },
        ),
        child: PageView.builder(
          controller: _controller,
          scrollDirection: Axis.vertical,
          // Mount adjacent video surfaces before they slide into view.
          allowImplicitScrolling: true,
          itemCount: widget.itemCount,
          itemBuilder: widget.itemBuilder,
        ),
      ),
    );
  }
}
