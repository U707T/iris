import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:iris/models/player.dart';
import 'package:iris/utils/throttled_seek.dart';

/// 短视频模式的进度拖动会话 (画面横向拖动 / 底部进度条拖动共用)。
///
/// - 本地预览位置让进度条实时跟手, 预览 seek 走 [ThrottledSeek]
///   (与主界面横向拖动共用同一套节流规则, 不再各写一份);
/// - 拖动时暂停播放, 松手后精确 seek 并恢复播放;
/// - session 计数保证连续拖动 / 松手后的"预览保留一小段时间"不会互相打架,
///   dispose 后延迟回调不再写状态。
class ShortVideoScrubSession {
  ShortVideoScrubSession({
    required this.readPlayer,
    DateTime Function()? clock,
  }) : _throttle = ThrottledSeek(
          seekTo: (target) => readPlayer().seek(target),
          interval: seekThrottle,
          clock: clock,
        );

  /// 取当前实时播放器实例。
  /// 播放期间本组件不会重建, build 时捕获的实例里 isPlaying / position
  /// 是过期的 (先暂停再拖动会误判为"未播放", 松手后不恢复播放)。
  final MediaPlayer Function() readPlayer;

  /// 拖动期间的本地预览位置 (null = 不在预览)
  final ValueNotifier<Duration?> preview = ValueNotifier(null);

  /// 预览 seek 的节流间隔
  static const Duration seekThrottle = Duration(milliseconds: 120);

  /// 松手后预览值保留时长 (避免松手瞬间进度先回跳再跳)
  static const Duration previewHold = Duration(milliseconds: 320);

  final ThrottledSeek _throttle;

  bool _alive = true;
  int _session = 0;
  bool _active = false;
  bool _resume = false;

  /// 开始拖动: [from] 为拖动起点 (实时播放位置)
  void start(Duration from) {
    _session++;
    _active = true;
    final player = readPlayer();
    _resume = player.isPlaying;
    if (_resume) player.pause();
    _throttle.begin();
    seek(from);
  }

  /// 拖动中: 更新预览位置并按节流发送 seek (第一次立即发送)
  void seek(Duration target) {
    if (!_active) return;
    preview.value = target;
    _throttle.seek(target);
  }

  /// 结束拖动: 补发最终位置并恢复播放, 预览保留一小段时间后收起
  void end() {
    if (!_active) return;
    _active = false;
    final resume = _resume;
    _resume = false;
    final session = ++_session;
    _throttle.end();
    if (resume) readPlayer().play();
    Future<void>.delayed(previewHold, () {
      if (_alive && _session == session) {
        preview.value = null;
      }
    });
  }

  void dispose() {
    _alive = false;
    preview.dispose();
  }
}
