import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/utils/toggle_mute_or_restore.dart';

/// 短视频模式的设备音量调节 (音量按钮上按住上下滑动 / 悬停滚轮微调)。
///
/// 与主界面上下拖动一致 —— 调的是**设备音量**(绝对音量, 手机音量键那个),
/// 直接写 FlutterVolumeController: 平台调用本身很快, 这里不做节流,
/// 否则声音会明显跟不上手指 (播放层的 setVolume 才需要节流)。
class ShortVideoDeviceVolumeController {
  /// 调节期间的本地预览值 (0~100, null = 不显示指示器)
  final ValueNotifier<double?> preview = ValueNotifier(null);

  /// 每滑动该像素数代表 1% 音量 (与主界面上下拖动一致: 200px = 100%)
  static const double dragPixelsPerPercent = 2.0;

  /// 调节结束 / 滚轮微调后, 预览值保留一小段时间再收起
  static const Duration previewHold = Duration(milliseconds: 320);

  bool _alive = true;
  int _session = 0;
  bool _active = false;

  /// 设备音量是否已读回 (读回前不处理位移, 免得拿旧值当基准)
  bool _ready = false;

  /// 调节开始时的设备音量 (0~100) 与按下位置
  double _start = 0.0;
  double _startDy = 0.0;

  /// 滚轮微调用的设备音量基准: 并发读只发生一次, 两次快速滚动不会各自
  /// 读到旧值、后一次写入覆盖前一次 (表现为"滚了没反应")。
  Future<double>? _pendingRead;

  /// 写入串行链: 保证快速连续滚轮时设备音量按顺序落地, 最后写入的是最新值
  Future<void>? _writeChain;

  Future<void> _apply(double value) async {
    try {
      await FlutterVolumeController.setVolume(value / 100);
    } catch (e) {
      logger('Error setting volume: $e');
    }
  }

  /// 读当前设备音量 (0~100); 失败 / 平台不支持时回退到应用内音量设置
  Future<double> _read() async {
    try {
      final value = await FlutterVolumeController.getVolume();
      if (value != null) return (value * 100).clamp(0.0, 100.0);
    } catch (e) {
      logger('Error getting volume: $e');
    }
    return useAppStore().state.volume.toDouble();
  }

  void _write(double value) {
    final previous = _writeChain ?? Future<void>.value();
    _writeChain = previous.then((_) => _apply(value));
  }

  Future<double> _base() async {
    final current = preview.value;
    if (current != null) return current;

    final pending = _pendingRead ?? _read();
    _pendingRead = pending;
    try {
      final value = await pending;
      // 读取期间可能已有新的调节落地, 以最新值为准
      return preview.value ?? value;
    } finally {
      if (identical(_pendingRead, pending)) {
        _pendingRead = null;
      }
    }
  }

  void _schedulePreviewClear() {
    final session = ++_session;
    Future<void>.delayed(previewHold, () {
      if (_alive && _session == session) {
        preview.value = null;
      }
    });
  }

  void adjustStart(Offset globalPosition) {
    _session++;
    _active = true;
    _ready = false;
    _startDy = globalPosition.dy;
    preview.value = null;
    // 调节期间不弹系统音量条 (自己已经有指示器了), 与主界面上下拖动一致
    unawaited(FlutterVolumeController.updateShowSystemUI(false));
    // 设备音量只能异步读: 长按识别 (100ms) 到手指真正滑动之间通常够它读完
    final session = _session;
    unawaited(() async {
      final value = await _read();
      if (!_alive || !_active || _session != session) return;
      _start = value;
      _ready = true;
      preview.value = value;
    }());
  }

  void adjustUpdate(Offset globalPosition) {
    if (!_active || !_ready) return;
    // 应用处于静音时, 一旦真的开始滑动就先取消静音, 否则调了也听不到
    // (按住不滑动松手 = 点击, 不在这里处理, 免得把点击语义吃掉)
    if (useAppStore().state.isMuted) {
      unawaited(useAppStore().updateMute(false));
    }
    final delta = (_startDy - globalPosition.dy) / dragPixelsPerPercent;
    final value = (_start + delta).clamp(0.0, 100.0);
    preview.value = value;
    unawaited(_apply(value));
  }

  void adjustEnd() {
    if (!_active) return;
    _active = false;
    _ready = false;
    // 恢复系统音量条 (退出模式 / 结束调节后, 硬件音量键照常显示)
    unawaited(FlutterVolumeController.updateShowSystemUI(true));
    // 设备音量由系统自己记住, 无需落盘, 收起指示器即可
    _schedulePreviewClear();
  }

  /// PC: 指针悬停在音量按钮上滚轮 = 微调设备音量 (同时取代翻页)
  Future<void> wheel(double deltaPercent) async {
    if (useAppStore().state.isMuted) {
      unawaited(useAppStore().updateMute(false));
    }
    final base = await _base();
    final value = (base + deltaPercent).clamp(0.0, 100.0);
    preview.value = value;
    _write(value);
    _schedulePreviewClear();
  }

  void dispose() {
    _alive = false;
    preview.dispose();
    // 离开模式时把"不显示系统音量条"的开关恢复, 免得影响别处
    unawaited(FlutterVolumeController.updateShowSystemUI(true));
  }
}

/// 音量按钮: 点击 = 静音 / 取消静音 (只静音本应用, 应用音量为 0 时恢复 80);
/// 按住 0.1s 后上下滑动 = 调节**设备音量**(绝对音量, 与主界面上下拖动一致);
/// 仅按住按钮时生效, 不影响翻页 / 倍速 / 播放暂停。
class ShortVideoVolumeButton extends HookWidget {
  const ShortVideoVolumeButton({super.key, required this.volume});

  final ShortVideoDeviceVolumeController volume;

  /// 长按识别时长: 系统默认 500ms 太迟钝, 音量调节要求按住 100ms 就接管指针
  static const Duration _longPressDelay = Duration(milliseconds: 100);

  /// 判定为“滑动调音量”的最小竖直位移。
  /// 取 8px 而不是更小的值: 按住按钮的瞬间手指自然抖动通常有几像素,
  /// 阈值太小会把「按住想静音」误判成滑动 (改掉 1~3% 音量还不静音)。
  static const double _slideSlop = 8.0;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final appVolume = useAppStore().select(context, (state) => state.volume);
    final isMuted = useAppStore().select(context, (state) => state.isMuted);
    // 长按已识别 (按住期间按钮高亮)
    final holding = useState(false);
    // 长按之后确实滑动了 (没滑动就松手 = 点击)
    final sliding = useState(false);
    // 长按起点, 作为滑动的基准位置
    final anchor = useRef(Offset.zero);

    /// 点击语义: 静音 / 取消静音 (音量为 0 时恢复到 80), 与主界面共用
    void onPressStart(LongPressStartDetails details) {
      anchor.value = details.globalPosition;
      holding.value = true;
      sliding.value = false;
      // 长按一识别就进入调节: 立刻去读设备音量并显示出指示器,
      // 手指真正滑动时基准值已经就绪 (没有"先等半秒才开始"的感觉)
      volume.adjustStart(anchor.value);
    }

    void onPressMove(LongPressMoveUpdateDetails details) {
      if (!holding.value) return;
      if (!sliding.value) {
        // 抖动不算滑动 (此时松手仍按点击处理)
        if (details.offsetFromOrigin.dy.abs() < _slideSlop) return;
        sliding.value = true;
      }
      volume.adjustUpdate(details.globalPosition);
    }

    void onPressEnd() {
      // 长按没识别 (快速点击): 交给 IconButton 的点击回调
      if (!holding.value) return;
      final wasSliding = sliding.value;
      holding.value = false;
      sliding.value = false;
      volume.adjustEnd();
      if (!wasSliding) {
        // 按住但没滑动 = 点击 (长按已接管指针, IconButton 收不到点击)
        toggleMuteOrRestore();
      }
    }

    return MergeSemantics(
      child: Semantics(
        label: t.volume,
        child: RawGestureDetector(
          // 在按钮上按住后上下滑动: 长按识别器由按钮自己持有 (100ms),
          // PageView 的翻页 / 外层的手势都会在竞争中被拒绝
          gestures: <Type, GestureRecognizerFactory>{
            LongPressGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
              () => LongPressGestureRecognizer(duration: _longPressDelay),
              (instance) {
                instance.onLongPressStart = onPressStart;
                instance.onLongPressMoveUpdate = onPressMove;
                instance.onLongPressEnd = (details) => onPressEnd();
                instance.onLongPressCancel = onPressEnd;
              },
            ),
          },
          child: Listener(
            // PC: 指针悬停在按钮上滚轮 = 微调设备音量 (拦截并取代翻页)
            onPointerSignal: (event) {
              if (event is! PointerScrollEvent) return;
              GestureBinding.instance.pointerSignalResolver
                  .register(event, (resolved) {
                final scrollEvent = resolved as PointerScrollEvent;
                final dy = scrollEvent.scrollDelta.dy;
                if (dy == 0) return;
                // 一格 (约 100px) 约 5% (1~10 之间)
                final step = (dy.abs() / 20).ceil().clamp(1, 10).toDouble();
                unawaited(volume.wheel(dy < 0 ? step : -step));
              });
            },
            child: ValueListenableBuilder<double?>(
              valueListenable: volume.preview,
              builder: (context, preview, _) {
                final level = (preview ?? appVolume.toDouble()).round();
                return Material(
                  color: holding.value ? Colors.black54 : Colors.black38,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: IconButton(
                    icon: Icon(
                      isMuted || level == 0
                          ? Icons.volume_off_rounded
                          : level < 50
                              ? Icons.volume_down_rounded
                              : Icons.volume_up_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    onPressed: toggleMuteOrRestore,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// 音量调节指示 (长按滑动时显示在画面中央)
class ShortVideoVolumeIndicator extends StatelessWidget {
  const ShortVideoVolumeIndicator({super.key, required this.volume});

  final double volume;

  @override
  Widget build(BuildContext context) {
    final level = volume.round();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 18, 12),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            level == 0
                ? Icons.volume_off_rounded
                : level < 50
                    ? Icons.volume_down_rounded
                    : Icons.volume_up_rounded,
            color: Colors.white,
            size: 24,
          ),
          const SizedBox(width: 12),
          Text(
            '$level%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}
