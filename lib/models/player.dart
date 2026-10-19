import 'dart:typed_data';
import 'package:material_ui/material_ui.dart';
import 'package:iris/models/file.dart';
import 'package:media_kit/media_kit.dart' as media_kit;
import 'package:media_kit_video/media_kit_video.dart' as media_kit_video;
import 'package:video_player/video_player.dart';

class MediaPlayer {
  final bool isInitializing;
  final bool isPlaying;

  /// 打开 / 装载当前媒体时的错误信息; null 表示没有错误。
  /// 由播放器后端在 `init()` 失败时写入, 供界面显示"无法播放"并提供重试。
  final String? error;

  /// 重新装载当前媒体 (错误界面上的"重试"按钮); null 表示不可重试。
  final Future<void> Function()? retry;
  final List<Subtitle> externalSubtitles;
  final Duration position;
  final Duration duration;
  final Duration buffer;
  final double width;
  final double height;
  final Future<void> Function() saveProgress;
  final Future<void> Function() play;
  final Future<void> Function() pause;
  final Future<void> Function(int) backward;
  final Future<void> Function(int) forward;
  final Future<void> Function() stepBackward;
  final Future<void> Function() stepForward;
  final Future<void> Function(Duration) seek;

  /// 截取当前画面, 返回编码后的图片数据, 失败返回 null
  final Future<Uint8List?> Function({bool includeSubtitles})? screenshot;

  /// 获取播放统计信息, 返回空 Map 表示暂不可用
  final Map<String, String> Function()? getStats;

  MediaPlayer({
    required this.isInitializing,
    required this.isPlaying,
    this.error,
    this.retry,
    required this.externalSubtitles,
    required this.position,
    required this.duration,
    required this.buffer,
    required this.width,
    required this.height,
    required this.saveProgress,
    required this.play,
    required this.pause,
    required this.backward,
    required this.forward,
    required this.stepBackward,
    required this.stepForward,
    required this.seek,
    this.screenshot,
    this.getStats,
  });
}

class MediaKitPlayer extends MediaPlayer {
  final media_kit.Player player;
  final media_kit_video.VideoController controller;
  final media_kit.SubtitleTrack subtitle;
  final List<media_kit.SubtitleTrack> subtitles;
  final media_kit.AudioTrack audio;
  final List<media_kit.AudioTrack> audios;

  MediaKitPlayer({
    required this.player,
    required this.controller,
    required this.subtitle,
    required this.subtitles,
    required super.externalSubtitles,
    required this.audio,
    required this.audios,
    required super.isInitializing,
    required super.isPlaying,
    super.error,
    super.retry,
    required super.position,
    required super.duration,
    required super.buffer,
    required super.width,
    required super.height,
    required super.saveProgress,
    required super.play,
    required super.pause,
    required super.backward,
    required super.forward,
    required super.stepBackward,
    required super.stepForward,
    required super.seek,
    super.screenshot,
    super.getStats,
  });
}

class FvpPlayer extends MediaPlayer {
  final VideoPlayerController controller;
  final ValueNotifier<int?> externalSubtitle;

  FvpPlayer({
    required this.controller,
    required super.isInitializing,
    required super.isPlaying,
    super.error,
    super.retry,
    required this.externalSubtitle,
    required super.externalSubtitles,
    required super.position,
    required super.duration,
    required super.buffer,
    required super.width,
    required super.height,
    required super.saveProgress,
    required super.play,
    required super.pause,
    required super.backward,
    required super.forward,
    required super.stepBackward,
    required super.stepForward,
    required super.seek,
    super.screenshot,
    super.getStats,
  });
}
