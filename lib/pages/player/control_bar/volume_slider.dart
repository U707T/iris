import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/store/use_app_store.dart';

class VolumeSlider extends HookWidget {
  const VolumeSlider({
    super.key,
    required this.showControl,
    this.color,
  });

  final void Function() showControl;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final volume = useAppStore().select(context, (state) => state.volume);
    final isMuted = useAppStore().select(context, (state) => state.isMuted);

    return ExcludeFocus(
      child: SizedBox(
        width: 128,
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            thumbColor: color,
            activeTrackColor: color?.withAlpha(222),
            inactiveTrackColor: color?.withAlpha(99),
            thumbShape: RoundSliderThumbShape(
              enabledThumbRadius: 5.6,
            ),
            overlayShape: const RoundSliderOverlayShape(
              overlayRadius: 4,
            ),
            trackHeight: 2.4,
          ),
          child: Slider(
            value: isMuted ? 0 : volume.toDouble(),
            onChanged: (value) {
              showControl();
              useAppStore().updateMute(false);
              useAppStore().updateVolume((value).toInt());
            },
            min: 0,
            max: 100,
          ),
        ),
      ),
    );
  }
}
