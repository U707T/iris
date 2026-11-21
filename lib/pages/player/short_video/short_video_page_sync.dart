import 'package:flutter/widgets.dart';

/// Replaces a previous programmatic animation even if the new destination is
/// still the rounded visible page. Scroll notifications while syncing are not
/// user navigation and must not be committed back to the queue.
class ShortVideoPageSync {
  ShortVideoPageSync(this.controller);
  final PageController controller;
  int _generation = 0;
  bool _alive = true;
  bool isSyncing = false;

  Future<void> syncTo(int target) async {
    if (!_alive || !controller.hasClients || target < 0) return;
    final page = controller.page ?? controller.initialPage.toDouble();
    // A settled user swipe already reached this exact offset. A jump here would
    // emit a second scroll activity and can interrupt PageView's own motion.
    if (!isSyncing &&
        !controller.position.isScrollingNotifier.value &&
        (page - target).abs() < 0.000001) {
      return;
    }
    final generation = ++_generation;
    isSyncing = true;
    try {
      if (page.round() == target) {
        // jumpTo cancels the old ScrollActivity even at the same offset.
        controller.jumpToPage(target);
      } else {
        await controller.animateToPage(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    } finally {
      if (_alive && generation == _generation) isSyncing = false;
    }
  }

  void dispose() {
    _alive = false;
    _generation++;
    isSyncing = false;
  }
}
