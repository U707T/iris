import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/utils/refresh_play_queue.dart';

/// 「刷新播放列表」的 UI 侧收尾：回扫 + 一条 snack bar。
///
/// 回扫本身是纯逻辑（`utils/refresh_play_queue.dart`），这里只负责反馈。
/// 分开放是因为 utils 不该 import material —— 一个扫码函数没必要知道 snack bar。
///
/// 大目录回扫要几百毫秒：期间若又从菜单里点了一次，会变成两次并发扫描 +
/// 两次落盘，所以用文件内的标记挡连点。
bool _refreshing = false;

Future<void> refreshPlaylistWithFeedback(BuildContext context) async {
  if (_refreshing) return;
  _refreshing = true;

  final t = getLocalizations(context);
  int? count;
  try {
    count = await refreshPlayQueue();
  } catch (e) {
    logger('Refresh play queue failed: $e');
  } finally {
    _refreshing = false;
  }

  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(
        count == null
            ? t.play_queue_refresh_failed
            : t.play_queue_refreshed(count),
      ),
    ),
  );
}
