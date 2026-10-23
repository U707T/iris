import 'package:material_ui/material_ui.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/control_bar/control_bar_slider.dart';
import 'package:iris/pages/player/gesture/seek_hub.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:iris/utils/format_duration_to_minutes.dart';
import 'package:provider/provider.dart';

/// 控制栏收起时的极简进度浮层（标题 + 细进度条 + 时间）。
///
/// 双击快进 / 快退、画面横滑拖动时都会显示，位置与读数**和短视频模式一致**：
/// 顶部标题、底部进度条、左下时间，并且跟随 [seekHub] 的预览值实时更新
/// （旧实现只读播放器位置，拖动时读数明显滞后）。
class MinimalProgressOverlay extends StatelessWidget {
  const MinimalProgressOverlay({
    super.key,
    required this.title,
    required this.file,
  });

  final String title;
  final FileItem? file;

  @override
  Widget build(BuildContext context) {
    final progress =
        context.select<MediaPlayer, ({Duration position, Duration duration})>(
      (player) => (position: player.position, duration: player.duration),
    );

    const overlayTextStyle = TextStyle(
      color: Colors.white,
      decoration: TextDecoration.none,
      shadows: [
        Shadow(
          color: Colors.black,
          offset: Offset(0, 0),
          blurRadius: 1,
        ),
      ],
    );

    final isShowControl =
        usePlayerUiStore().select(context, (state) => state.isShowControl);
    final isShowProgress =
        usePlayerUiStore().select(context, (state) => state.isShowProgress);

    if (!isShowProgress || isShowControl || file?.type != ContentType.video) {
      return const SizedBox.shrink();
    }

    return ValueListenableBuilder<Duration?>(
      valueListenable: seekHub.preview,
      builder: (context, preview, _) {
        final display = preview ?? progress.position;
        return Stack(
          children: [
            Positioned(
              left: 12,
              top: 12 + MediaQuery.viewPaddingOf(context).top,
              child: Text(
                title,
                style: overlayTextStyle.copyWith(fontSize: 20, height: 1),
              ),
            ),
            Positioned(
              left: -28,
              right: -28,
              bottom: -16,
              height: 32,
              child: ControlBarSlider(
                disabled: true,
              ),
            ),
            Positioned(
              left: 12,
              bottom: 6,
              child: Text(
                '${formatDurationToMinutes(display)} / ${formatDurationToMinutes(progress.duration)}',
                style: overlayTextStyle.copyWith(
                  fontSize: 16,
                  height: 2,
                  fontWeight: preview != null ? FontWeight.w600 : null,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
