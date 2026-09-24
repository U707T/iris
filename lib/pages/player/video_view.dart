import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/player.dart';
import 'package:iris/models/store/player_ui_state.dart';
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
    final rotateMode =
        usePlayerUiStore().select(context, (state) => state.rotateMode);

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

    Widget result = video;

    // 旋转 / 镜像
    switch (rotateMode) {
      case RotateMode.none:
        break;
      case RotateMode.rotate90:
        result = RotatedBox(quarterTurns: 3, child: result);
        break;
      case RotateMode.rotate180:
        result = RotatedBox(quarterTurns: 2, child: result);
        break;
      case RotateMode.rotate270:
        result = RotatedBox(quarterTurns: 1, child: result);
        break;
      case RotateMode.flipH:
        result = Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()..scaleByDouble(-1.0, 1.0, 1.0, 1.0),
          child: result,
        );
        break;
      case RotateMode.flipV:
        result = Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()..scaleByDouble(1.0, -1.0, 1.0, 1.0),
          child: result,
        );
        break;
    }

    // 手动无级缩放: 以画面中心为基准缩放
    if (zoom != 1.0) {
      result = Transform.scale(scale: zoom, child: result);
    }

    return result;
  }
}
