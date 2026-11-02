import 'package:flutter/gestures.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/control_bar/control_bar.dart';
import 'package:iris/pages/player/title_bar.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:iris/widgets/drag_area.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// 标题栏 + 控制栏（主窗口的唯一一处控制层）。
///
/// 显隐规则本身不在这里：`ControlsAutoHide` 决定「什么时候该收起」，
/// 本文件只负责把 [PlayerUiStore.isShowControl] 渲染成动画。
///
/// 显隐动画的两个要点（都是 v2.6.1 之前实际存在的体验问题）：
/// 1. **按自身尺寸滑出**：以前写死 `bottom: -128`，而窄屏两行控制栏实测
///    140px 高 —— 收起后屏幕底部会留一条 12px 的按钮条，而且还能点到。
///    现在用 [AnimatedSlide]（偏移量是自身尺寸的比例），布局怎么变都收得干净。
/// 2. **收起后不吃指针**：滑出屏幕的控件仍然参与命中测试的话，点击画面唤出
///    控制栏会失效（点击被看不见的按钮吃掉了），所以统一套 [IgnorePointer]。
class ControlsOverlay extends HookWidget {
  const ControlsOverlay({
    super.key,
    required this.file,
    required this.title,
    required this.showControl,
    required this.showControlForHover,
  });

  final FileItem? file;
  final String title;
  final Function() showControl;
  final Future<void> Function(Future<void> callback) showControlForHover;

  static const Duration animationDuration = Duration(milliseconds: 200);
  static const Curve animationCurve = Curves.easeInOutCubicEmphasized;

  @override
  Widget build(BuildContext context) {
    final saveProgress = context.read<MediaPlayer>().saveProgress;

    final isShowControl =
        usePlayerUiStore().select(context, (state) => state.isShowControl);

    final contentColor = useMemoized(
        () => Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).colorScheme.onSurface
            : Theme.of(context).colorScheme.surface,
        [context]);

    final overlayColor = useMemoized(
        () =>
            WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
              if (states.contains(WidgetState.pressed)) {
                return contentColor.withValues(alpha: 0.2);
              } else if (states.contains(WidgetState.hovered)) {
                return contentColor.withValues(alpha: 0.2);
              }
              return null;
            }),
        [contentColor]);

    void onHover(PointerHoverEvent event) {
      if (event.kind != PointerDeviceKind.touch) {
        showControl();
      }
    }

    // 全面屏 / 刘海屏: 顶部控件让出系统安全区, 视频画面本身不动 (仍然居中)。
    // 安全区放在 _SlideHide **内部**: 滑出量按「自身总高（含安全区）」算，
    // 否则刘海屏上滑出后标题栏会正好停在状态栏那一条里。
    final double topInset = MediaQuery.viewPaddingOf(context).top;

    // 音频没有画面可看, 控制层一直留着 (与播放器本体一致)
    final bool visible = isShowControl || file?.type != ContentType.video;

    return Stack(
      children: [
        // 标题栏
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _SlideHide(
            visible: visible,
            begin: const Offset(0, -1),
            child: Padding(
              padding: EdgeInsets.only(top: topInset),
              // 安全区条带不加命中区: 那里点下去应该落到画面上
              child: MouseRegion(
                onEnter: (_) => usePlayerUiStore().updateIsHovering(true),
                // 离开只解除悬停, 不主动唤出: 指针移开控制栏不该把控制栏叫回来。
                // 计时由 ControlsAutoHide.sync 重新开始。
                onExit: (_) => usePlayerUiStore().updateIsHovering(false),
                onHover: onHover,
                child: GestureDetector(
                  onTap: () => showControl(),
                  child: DragArea(
                    child: TitleBar(
                      title: title,
                      actions: [const SizedBox(width: 8)],
                      color: contentColor,
                      overlayColor: overlayColor,
                      saveProgress: () => saveProgress(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // 控制栏
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _SlideHide(
            visible: visible,
            begin: const Offset(0, 1),
            child: MouseRegion(
              onEnter: (_) => usePlayerUiStore().updateIsHovering(true),
              onExit: (_) => usePlayerUiStore().updateIsHovering(false),
              onHover: onHover,
              child: GestureDetector(
                onTap: () => showControl(),
                child: ControlBar(
                  showControl: showControl,
                  showControlForHover: showControlForHover,
                  color: contentColor,
                  overlayColor: overlayColor,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 控制层的一上 / 一下滑出动画。
///
/// [AnimatedSlide] 的 offset 是**自身尺寸的比例**，所以不需要预先知道
/// 控制栏有多高（两行布局 / 系统字号放大都会变）；滑出屏幕之后再用
/// [IgnorePointer] 把命中测试关掉，避免「看不见但能吃点击」。
class _SlideHide extends StatelessWidget {
  const _SlideHide({
    required this.visible,
    required this.begin,
    required this.child,
  });

  /// 隐藏时滑向哪个方向（一个自身尺寸的比例）
  final Offset begin;
  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: ExcludeSemantics(
        excluding: !visible,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : begin,
          duration: ControlsOverlay.animationDuration,
          curve: ControlsOverlay.animationCurve,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: ControlsOverlay.animationDuration,
            curve: ControlsOverlay.animationCurve,
            child: child,
          ),
        ),
      ),
    );
  }
}
