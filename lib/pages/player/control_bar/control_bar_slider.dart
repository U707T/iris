import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/gesture/seek_hub.dart';
import 'package:iris/pages/player/gesture/seek_session.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:iris/utils/format_duration_to_minutes.dart';
import 'package:provider/provider.dart';

class ControlBarSlider extends HookWidget {
  const ControlBarSlider({
    super.key,
    this.showControl,
    this.disabled = false,
    this.color,
  });

  final void Function()? showControl;
  final bool disabled;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final progress = context.select<
        MediaPlayer,
        ({
          Duration position,
          Duration duration,
          Duration buffer,
        })>(
      (player) => (
        position: player.position,
        duration: player.duration,
        buffer: player.buffer,
      ),
    );

    // 拖动进度条走的是与画面横滑**同一份**会话：
    // 暂停 -> 只更新预览 -> 停住才让画面跟上 -> 松手精确落定并续播。
    // 旧实现自己维护 ThrottledSeek + wasPlaying，行为和手势那边对不上。
    final session = useMemoized(
      () => SeekSession(
        readPlayer: () => context.read<MediaPlayer>(),
        preview: seekHub.preview,
      ),
      const [],
    );
    useEffect(() {
      return session.dispose;
    }, [session]);

    final double max = progress.duration.inMilliseconds.toDouble();
    final double bufferValue =
        progress.buffer.inMilliseconds.toDouble().clamp(0.0, max);

    return ValueListenableBuilder<Duration?>(
      valueListenable: seekHub.preview,
      builder: (context, preview, _) {
        final displayPosition = preview ?? progress.position;
        final double displayValue =
            displayPosition.inMilliseconds.toDouble().clamp(0.0, max);
        final bool isPreviewing = preview != null;

        return ExcludeFocus(
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            child: Row(
              children: [
                Visibility(
                  visible: !disabled,
                  child: Text(
                    formatDurationToMinutes(displayPosition),
                    style: TextStyle(
                      color: color,
                      height: 2,
                      // 预览期间加重，明确「这是你要跳到的位置」
                      fontWeight: isPreviewing ? FontWeight.w600 : null,
                    ),
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: color?.withAlpha(222) ??
                          Theme.of(context).colorScheme.primary,
                      inactiveTrackColor: color?.withAlpha(70) ??
                          Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.25),
                      secondaryActiveTrackColor: color?.withAlpha(120) ??
                          Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.4),
                      thumbColor: color ?? Theme.of(context).colorScheme.primary,
                      thumbShape: RoundSliderThumbShape(
                        enabledThumbRadius: disabled ? 0 : 6,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 12,
                      ),
                      trackHeight: 4,
                      trackShape: const _CustomTrackShape(),
                    ),
                    child: Slider(
                      value: displayValue,
                      secondaryTrackValue: bufferValue,
                      min: 0,
                      max: max > 0 ? max : 1.0,
                      onChanged: disabled
                          ? null
                          : (value) {
                              showControl?.call();
                              session.seekTo(
                                Duration(milliseconds: value.toInt()),
                              );
                            },
                      onChangeStart: disabled
                          ? null
                          : (value) {
                              usePlayerUiStore().updateIsSeeking(true);
                              session.start(
                                Duration(milliseconds: value.toInt()),
                              );
                              session.seekTo(
                                Duration(milliseconds: value.toInt()),
                              );
                            },
                      onChangeEnd: disabled
                          ? null
                          : (value) {
                              session.seekTo(
                                Duration(milliseconds: value.toInt()),
                              );
                              session.end();
                              usePlayerUiStore().updateIsSeeking(false);
                            },
                    ),
                  ),
                ),
                Visibility(
                  visible: !disabled,
                  child: Text(
                    formatDurationToMinutes(progress.duration),
                    style: TextStyle(color: color, height: 2),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CustomTrackShape extends RoundedRectSliderTrackShape {
  const _CustomTrackShape();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    if (sliderTheme.trackHeight == null || sliderTheme.trackHeight! <= 0) {
      return;
    }

    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final Radius trackRadius = Radius.circular(trackRect.height / 2);

    final Paint inactivePaint = Paint()
      ..color = sliderTheme.inactiveTrackColor!;
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, trackRadius),
      inactivePaint,
    );

    if (secondaryOffset != null) {
      final Paint secondaryPaint = Paint()
        ..color = sliderTheme.secondaryActiveTrackColor!;
      final Rect secondaryRect = Rect.fromLTRB(
        trackRect.left,
        trackRect.top,
        secondaryOffset.dx,
        trackRect.bottom,
      );
      context.canvas.drawRRect(
        RRect.fromRectAndRadius(secondaryRect, trackRadius),
        secondaryPaint,
      );
    }

    final Paint activePaint = Paint()..color = sliderTheme.activeTrackColor!;
    final Rect activeRect = Rect.fromLTRB(
      trackRect.left,
      trackRect.top,
      thumbCenter.dx,
      trackRect.bottom,
    );
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(activeRect, trackRadius),
      activePaint,
    );
  }
}
