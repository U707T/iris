import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/player.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

class VideoView extends HookWidget {
  const VideoView({
    super.key,
    required this.fit,
  });

  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final player = context.read<MediaPlayer>();
    final zoom = usePlayerUiStore().select(context, (state) => state.zoom);

    final Widget video = switch (player) {
      MediaKitPlayer player => Video(
          controller: player.controller,
          controls: NoVideoControls,
          fit: fit == BoxFit.none ? BoxFit.contain : fit,
        ),
      FvpPlayer player => FittedBox(
          fit: fit,
          child: SizedBox(
            width: player.width,
            height: player.height,
            child: VideoPlayer(player.controller),
          ),
        ),
      _ => const SizedBox.shrink(),
    };

    if (zoom == 1.0) return video;

    // 手动无级缩放: 以画面中心为基准缩放
    return Transform.scale(
      scale: zoom,
      child: video,
    );
  }
}
