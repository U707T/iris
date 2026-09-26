import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:image/image.dart' as img;
import 'package:iris/models/player.dart';
import 'package:iris/models/store/player_ui_state.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/utils/screenshot.dart';

/// 截取当前播放画面并保存, 同时给出提示。
///
/// [includeSubtitles] 为 true 时会把字幕一起截入 (仅 Media Kit 后端支持)。
/// 保存前会按当前画面的旋转/镜像状态处理截图方向。
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
    var bytes = await screenshotFn(includeSubtitles: includeSubtitles);
    if (bytes == null || bytes.isEmpty) {
      messenger?.showSnackBar(
        SnackBar(content: Text(t.screenshot_failed)),
      );
      return;
    }

    // 跟随画面的旋转 / 镜像 (在后台 isolate 处理, 避免大图阻塞界面)
    final rotateMode = usePlayerUiStore().state.rotateMode;
    if (rotateMode != RotateMode.none) {
      bytes =
          await compute(_applyRotateMode, [bytes, rotateMode.index]) ?? bytes;
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

/// 按画面的旋转 / 镜像状态处理截图 (transform 在后台 isolate 中执行)。
Uint8List? _applyRotateMode(List<Object> args) {
  final bytes = args[0] as Uint8List;
  final mode = RotateMode.values[args[1] as int];

  try {
    final isPng = bytes.length > 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;

    var image = img.decodeImage(bytes);
    if (image == null) return bytes;

    switch (mode) {
      case RotateMode.none:
        break;
      case RotateMode.rotate90:
        // 画面为逆时针 90° (RotatedBox quarterTurns: 3)
        image = img.copyRotate(image, angle: 270);
        break;
      case RotateMode.rotate180:
        image = img.copyRotate(image, angle: 180);
        break;
      case RotateMode.rotate270:
        // 画面为顺时针 90° (RotatedBox quarterTurns: 1)
        image = img.copyRotate(image, angle: 90);
        break;
      case RotateMode.flipH:
        image = img.flipHorizontal(image);
        break;
      case RotateMode.flipV:
        image = img.flipVertical(image);
        break;
    }

    final out =
        isPng ? img.encodePng(image) : img.encodeJpg(image, quality: 95);
    return Uint8List.fromList(out);
  } catch (e) {
    logger('Error rotating screenshot: $e');
    return bytes;
  }
}
