import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/globals.dart' show minZoom, maxZoom;
import 'package:iris/models/store/player_ui_state.dart';
import 'package:iris/utils/platform.dart';
import 'package:window_manager/window_manager.dart';

class PlayerUiStore extends Store<PlayerUiState> {
  PlayerUiStore() : super(const PlayerUiState());

  void updateAspectRatio(double ratio) {
    set(state.copyWith(aspectRatio: ratio));
  }

  void updateZoom(double zoom) {
    final clamped = zoom < minZoom
        ? minZoom
        : zoom > maxZoom
            ? maxZoom
            : zoom;
    set(state.copyWith(zoom: clamped));
  }

  void resetZoom() => updateZoom(1.0);

  void updateRotateMode(RotateMode mode) {
    set(state.copyWith(rotateMode: mode));
  }

  /// 顺时针循环切换旋转角度: 0 -> 90 -> 180 -> 270 -> 0
  void cycleRotation() {
    switch (state.rotateMode) {
      case RotateMode.none:
      case RotateMode.flipH:
      case RotateMode.flipV:
        set(state.copyWith(rotateMode: RotateMode.rotate90));
        break;
      case RotateMode.rotate90:
        set(state.copyWith(rotateMode: RotateMode.rotate180));
        break;
      case RotateMode.rotate180:
        set(state.copyWith(rotateMode: RotateMode.rotate270));
        break;
      case RotateMode.rotate270:
        set(state.copyWith(rotateMode: RotateMode.none));
        break;
    }
  }

  void toggleFlipH() {
    set(state.copyWith(
      rotateMode:
          state.rotateMode == RotateMode.flipH ? RotateMode.none : RotateMode.flipH,
    ));
  }

  void toggleFlipV() {
    set(state.copyWith(
      rotateMode:
          state.rotateMode == RotateMode.flipV ? RotateMode.none : RotateMode.flipV,
    ));
  }

  void resetRotate() => updateRotateMode(RotateMode.none);

  void toggleIsShowStats() {
    set(state.copyWith(isShowStats: !state.isShowStats));
  }

  void updateIsShowStats(bool isShowStats) {
    set(state.copyWith(isShowStats: isShowStats));
  }

  Future<void> toggleIsAlwaysOnTop() async {
    if (isDesktop) {
      windowManager.setAlwaysOnTop(!state.isAlwaysOnTop);
      set(state.copyWith(isAlwaysOnTop: !state.isAlwaysOnTop));
    }
  }

  /// 全屏开关 (桌面端)。
  /// 参数是「设置为」的目标值, 不是「切换」—— 旧实现忽略参数直接取反,
  /// 任何显式传值的调用方 (如 Escape 传 false) 都只是在碰巧下能用。
  Future<void> updateFullScreen(bool bool) async {
    if (!isDesktop) return;
    windowManager.setFullScreen(bool);
    set(state.copyWith(isFullScreen: bool));
  }

  void updateIsSeeking(bool bool) {
    set(state.copyWith(isSeeking: bool));
  }

  void updateIsHovering(bool bool) {
    set(state.copyWith(isHovering: bool));
  }

  void updateIsShowControl(bool bool) {
    set(state.copyWith(isShowControl: bool));
  }

  void updateIsShowProgress(bool bool) {
    set(state.copyWith(isShowProgress: bool));
  }

  void updateShortVideoMode(bool bool) {
    set(state.copyWith(isShortVideoMode: bool));
  }
}

PlayerUiStore usePlayerUiStore() => create(() => PlayerUiStore());
