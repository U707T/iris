import 'package:flutter/foundation.dart';
import 'package:iris/pages/player/gesture/seek_hud.dart';

/// 拖动 seek 的共享预览与提示（主窗口 / 短视频模式共用同一个实例）。
///
/// 为什么是一个模块级对象而不是 store 字段 / 逐层传参：
/// - 需要读预览的有四处（主窗口进度条、主窗口迷你进度、短视频底部时间、短视频进度条），
///   它们分散在两条互不相邻的组件链上（GestureOverlay / ControlsOverlay / ShortVideoView），
///   逐层传一个 ValueNotifier 会把两条链都串成"传话筒"；
/// - 写预览的只有拖动会话（[SeekSession]），读的是 UI，天然是"一个生产者、多个消费者"；
/// - 与 `player_handoff.dart` 同一套约定：跨宿主的会话级共享状态放在模块级。
///
/// 只放**瞬时**状态（拖动中 / 松手后短暂保留），不参与持久化。
class SeekHub {
  /// 拖动期间的预览位置（null = 不在拖动 / 已收起）
  final ValueNotifier<Duration?> preview = ValueNotifier(null);

  /// 快进 / 快退提示（双击步长 + 拖动读数）
  final SeekHudController hud = SeekHudController();

  /// 测试用：把状态清干净（全局对象在用例之间会互相影响）
  void reset() {
    preview.value = null;
    hud.clear();
  }
}

/// 全局共享实例（UI 与拖动会话都从这里取）
final SeekHub seekHub = SeekHub();
