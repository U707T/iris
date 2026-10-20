import 'dart:typed_data';
import 'package:media_kit/media_kit.dart' as media_kit;
import 'package:media_kit_video/media_kit_video.dart' as media_kit_video;

class MediaPlayer {
  final bool isInitializing;
  final bool isPlaying;
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
  final Future<Uint8List?> Function()? screenshot;

  /// 获取播放统计信息, 返回空 Map 表示暂不可用
  final Map<String, String> Function()? getStats;

  MediaPlayer({
    required this.isInitializing,
    required this.isPlaying,
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
  final media_kit.AudioTrack audio;
  final List<media_kit.AudioTrack> audios;

  MediaKitPlayer({
    required this.player,
    required this.controller,
    required this.audio,
    required this.audios,
    required super.isInitializing,
    required super.isPlaying,
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
