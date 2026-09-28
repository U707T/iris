import 'package:iris/utils/logger.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 等待视频输出渲染出第一帧 (带超时兜底)。
///
/// 解决"开局先响声音、画面还黑着"的问题: 视频输出 (纹理 / 渲染表面) 与首帧
/// 解码通常比音频慢, 若这期间已经开始播放, 就会出现有声音没画面。
/// 用法: 以暂停方式 `open()` 之后、真正 `play()` 之前调用 —— 首帧就绪再出声,
/// 音画一起出现。
///
/// 注意:
/// - 只对**视频**调用 (音频永远等不到首帧), 且必须带超时兜底,
///   个别文件 / 平台上该信号可能不会到达, 不能让播放卡死;
/// - Android 上该信号实际是"视频参数就绪"(画面尺寸已知) 的事件,
///   比真正的首帧渲染更早, 因此等待成本很低。
Future<void> waitForFirstFrame(
  VideoController controller, {
  Duration timeout = const Duration(milliseconds: 800),
}) async {
  try {
    await controller.waitUntilFirstFrameRendered.timeout(timeout);
  } catch (e) {
    logger('Wait for first frame failed '
        '(timeout ${timeout.inMilliseconds}ms): $e');
  }
}
