import 'package:flutter/material.dart';
import 'package:iris/models/player.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/utils/screenshot.dart';

/// 截取当前播放画面并保存, 同时给出提示。
///
/// [includeSubtitles] 为 true 时会把字幕一起截入 (仅 Media Kit 后端支持)。
Future<void> takeScreenshot(
  BuildContext context,
  MediaPlayer player, {
  bool includeSubtitles = true,
}) async {
  final t = getLocalizations(context);
  final messenger = ScaffoldMessenger.maybeOf(context);

  final screenshotFn = player.screenshot;
  if (screenshotFn == null) {
    messenger?.showSnackBar(
      SnackBar(content: Text(t.screenshot_failed)),
    );
    return;
  }

  try {
    final bytes =
        await screenshotFn(includeSubtitles: includeSubtitles);
    if (bytes == null || bytes.isEmpty) {
      messenger?.showSnackBar(
        SnackBar(content: Text(t.screenshot_failed)),
      );
      return;
    }

    final isPng = bytes.length > 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;

    final path = await saveScreenshot(
      bytes: bytes,
      fileNamePrefix: 'IRIS',
      extension: isPng ? 'png' : 'jpg',
    );

    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          path != null ? '${t.screenshot_saved}: $path' : t.screenshot_failed,
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  } catch (e) {
    logger('Screenshot error: $e');
    messenger?.showSnackBar(
      SnackBar(content: Text(t.screenshot_failed)),
    );
  }
}
