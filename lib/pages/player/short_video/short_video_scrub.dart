import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:iris/models/player.dart';

/// 短视频模式的进度拖动会话 (画面横向拖动 / 底部进度条拖动共用)。
///
/// - 本地预览位置让进度条实时跟手, 预览 seek 做节流;
/// - 拖动时暂停播放, 松手后精确 seek 并恢复播放;
/// - session 计数保证连续拖动 / 松手后的"预览保留一小段时间"不会互相打架,
///   dispose 后延迟回调不再写状态。
class ShortVideoScrubSession {
  ShortVideoScrubSession({required this.readPlayer});

  /// 取当前实时播放器实例。
  /// 播放期间本组件不会重建, build 时捕获的实例里 isPlaying / position
  /// 是过期的 (先暂停再拖动会误判为"未播放", 松手后不恢复播放)。
  final MediaPlayer Function() readPlayer;

  /// 拖动期间的本地预览位置 (null = 不在预览)
  final ValueNotifier<Duration?> preview = ValueNotifier(null);

  /// 预览 seek 的节流间隔
  static const Duration seekThrottle = Duration(milliseconds: 140);

  /// 松手后预览值保留时长 (避免松手瞬间进度先回跳再跳)
  static const Duration previewHold = Duration(milliseconds: 320);

  bool _alive = true;
  int _session = 0;
  bool _active = false;
  bool _resume = false;
  DateTime? _lastSeekAt;

  /// 开始拖动: [from] 为拖动起点 (实时播放位置)
  void start(Duration from) {
    _session++;
    _active = true;
    final player = readPlayer();
    _resume = player.isPlaying;
    if (_resume) player.pause();
    _lastSeekAt = null;
    seek(from, force: true);
  }

  /// 拖动中: 更新预览位置并按节流发送 seek
  void seek(Duration target, {bool force = false}) {
    if (!force && !_active) return;
    preview.value = target;
    final now = DateTime.now();
    final last = _lastSeekAt;
    if (force || last == null || now.difference(last) >= seekThrottle) {
      _lastSeekAt = now;
      readPlayer().seek(target);
    }
  }

  /// 结束拖动: 精确 seek 到预览位置并恢复播放, 预览保留一小段时间后收起
  void end() {
    if (!_active) return;
    final target = preview.value;
    _active = false;
    _lastSeekAt = null;
    final resume = _resume;
    _resume = false;
    final session = ++_session;
    if (target != null) readPlayer().seek(target);
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
