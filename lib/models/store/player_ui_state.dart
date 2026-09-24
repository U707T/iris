import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flutter/foundation.dart';

part 'player_ui_state.freezed.dart';
part 'player_ui_state.g.dart';

/// 画面旋转 / 翻转模式
enum RotateMode {
  /// 不旋转
  none,

  /// 逆时针 90 度
  rotate90,

  /// 180 度
  rotate180,

  /// 逆时针 270 度 (顺时针 90 度)
  rotate270,

  /// 水平镜像
  flipH,

  /// 垂直镜像
  flipV,
}

@freezed
abstract class PlayerUiState with _$PlayerUiState {
  const factory PlayerUiState({
    @Default(0) double aspectRatio,
    @Default(1.0) double zoom,
    @Default(RotateMode.none) RotateMode rotateMode,
    @Default(false) bool isAlwaysOnTop,
    @Default(false) bool isFullScreen,
    @Default(false) bool isSeeking,
    @Default(false) bool isHovering,
    @Default(true) bool isShowControl,
    @Default(false) bool isShowProgress,
    @Default(false) bool isShowStats,
    @Default(false) bool isShortVideoMode,
  }) = _PlayerUiState;

  factory PlayerUiState.fromJson(Map<String, dynamic> json) =>
      _$PlayerUiStateFromJson(json);
}
