import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flutter/foundation.dart';

part 'player_ui_state.freezed.dart';
part 'player_ui_state.g.dart';

@freezed
abstract class PlayerUiState with _$PlayerUiState {
  const factory PlayerUiState({
    @Default(0) double aspectRatio,
    @Default(1.0) double zoom,
    @Default(false) bool isAlwaysOnTop,
    @Default(false) bool isFullScreen,
    @Default(false) bool isSeeking,
    @Default(false) bool isHovering,
    @Default(true) bool isShowControl,
    @Default(false) bool isShowProgress,
  }) = _PlayerUiState;

  factory PlayerUiState.fromJson(Map<String, dynamic> json) =>
      _$PlayerUiStateFromJson(json);
}
