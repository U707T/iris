import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:iris/utils/logger.dart';
import 'package:screen_brightness/screen_brightness.dart';

/// 纵向拖动调节的亮度 / 音量（主窗口与短视频模式共用一套换算）。
///
/// 旧实现（`use_brightness.dart` / `use_volume.dart`）是「先异步读、读到后置状态，
/// 位移用 `delta.dy` 逐帧累加」：
/// - 读回来之前的所有位移被丢掉（起手一顿）；
/// - 逐帧累加依赖每帧都收到事件，掉帧就会少算，快滑到顶 / 底时明显跟不上手。
///
/// 这里改成与进度同一套口径：**基准值 + 累计位移**（[pixelsPerFullScale] = 200px 满量程），
/// 读回来之前先把位移攒着，读完立即补上，不丢手势。
class PlayerLevels {
  /// 滑动多少逻辑像素走完满量程（0 → 100%）
  static const double pixelsPerFullScale = 200.0;

  /// 当前亮度（0~1，null = 还没读到 / 不在调节）
  final ValueNotifier<double?> brightness = ValueNotifier(null);

  /// 当前设备音量（0~1，null = 还没读到 / 不在调节）
  final ValueNotifier<double?> volume = ValueNotifier(null);

  bool _alive = true;
  bool _active = false;
  bool _left = true;
  double _startLevel = 0.0;
  bool _ready = false;

  /// 读回基准值之前攒下的位移（逻辑像素，向上为负）
  double? _pendingDy;

  /// 开始调节。[left] 为 true 时调亮度，false 时调设备音量。
  Future<void> start({required bool left}) async {
    if (!_alive) return;
    _active = true;
    _left = left;
    _ready = false;
    _pendingDy = null;
    if (!left) {
      // 调节期间不弹系统音量条（与短视频音量按钮一致）
      try {
        await FlutterVolumeController.updateShowSystemUI(false);
      } catch (e) {
        logger('Error hiding system volume UI: $e');
      }
    }
    final level = left ? await _readBrightness() : await _readVolume();
    if (!_alive || !_active || _left != left) return;
    _startLevel = level ?? _startLevel;
    _ready = true;
    // 指示器立即出现，不等到第一次位移
    (left ? brightness : volume).value = _startLevel;
    final pending = _pendingDy;
    if (pending != null) update(dy: pending);
  }

  /// 拖动中：[dy] 是相对按下点的累计纵向位移（向上为负 = 调大）。
  void update({required double dy}) {
    if (!_alive || !_active) return;
    if (!_ready) {
      _pendingDy = dy;
      return;
    }
    final target =
        (_startLevel - dy / pixelsPerFullScale).clamp(0.0, 1.0).toDouble();
    if (_left) {
      brightness.value = target;
      _applyBrightness(target);
      // 两端浮层共用中央位置：清掉对面残留，避免叠两层
      volume.value = null;
    } else {
      volume.value = target;
      _applyVolume(target);
      brightness.value = null;
    }
  }

  /// 松手：收起指示器并恢复系统音量条的自动显示
  Future<void> end() async {
    if (!_active) return;
    _active = false;
    _ready = false;
    _pendingDy = null;
    brightness.value = null;
    volume.value = null;
    if (!_left) {
      try {
        await FlutterVolumeController.updateShowSystemUI(true);
      } catch (e) {
        logger('Error restoring system volume UI: $e');
      }
    }
  }

  Future<double?> _readBrightness() async {
    try {
      return await ScreenBrightness.instance.application;
    } catch (e) {
      logger('Error getting brightness: $e');
      return null;
    }
  }

  Future<double?> _readVolume() async {
    try {
      return await FlutterVolumeController.getVolume();
    } catch (e) {
      logger('Error getting volume: $e');
      return null;
    }
  }

  void _applyBrightness(double value) => _writeBrightness(value);

  void _applyVolume(double value) => _writeVolume(value);

  // ------------------------------------------------------------------ 写入合并
  //
  // 拖动是每帧回调（60~120 次/秒），而亮度 / 音量都是跨线程的平台调用。
  // 逐帧发会出现两种问题：
  // - 平台侧排队，声音 / 亮度比手指晚几百毫秒（"跟不上手"）；
  // - 低端机上 method channel 被打满，反而掉帧。
  //
  // 这里做「串行 + 只保留最新值」：上一次还没返回就先记下来，返回后立刻补发最新的那个。
  // 既不积压，也不丢落点。

  double? _pendingBrightness;
  bool _writingBrightness = false;
  double? _pendingVolume;
  bool _writingVolume = false;

  void _writeBrightness(double value) {
    _pendingBrightness = value;
    if (_writingBrightness) return;
    unawaited(_flushBrightness());
  }

  Future<void> _flushBrightness() async {
    _writingBrightness = true;
    while (_pendingBrightness != null && _alive) {
      final value = _pendingBrightness!;
      _pendingBrightness = null;
      try {
        await ScreenBrightness.instance.setApplicationScreenBrightness(value);
      } catch (e) {
        logger('Error setting brightness: $e');
      }
    }
    _writingBrightness = false;
  }

  void _writeVolume(double value) {
    _pendingVolume = value;
    if (_writingVolume) return;
    unawaited(_flushVolume());
  }

  Future<void> _flushVolume() async {
    _writingVolume = true;
    while (_pendingVolume != null && _alive) {
      final value = _pendingVolume!;
      _pendingVolume = null;
      try {
        await FlutterVolumeController.setVolume(value);
      } catch (e) {
        logger('Error setting volume: $e');
      }
    }
    _writingVolume = false;
  }

  void dispose() {
    _alive = false;
    _active = false;
    _pendingBrightness = null;
    _pendingVolume = null;
    brightness.dispose();
    volume.dispose();
    // 退出播放页恢复系统亮度（沿用旧行为）
    try {
      ScreenBrightness.instance.resetApplicationScreenBrightness();
    } catch (e) {
      logger('Error resetting brightness: $e');
    }
  }
}
