import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/picture_in_picture.dart';
import 'package:iris/utils/platform.dart';
import 'package:iris/widgets/dialogs/show_choice_dialog.dart';
import 'package:iris/widgets/panel.dart';
import 'package:iris/widgets/setting_row.dart';

class Play extends HookWidget {
  const Play({super.key});

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);

    final autoResize = useAppStore().select(
      context,
      (state) => state.autoResize,
    );
    final bool alwaysPlayFromBeginning = useAppStore().select(
      context,
      (state) => state.alwaysPlayFromBeginning,
    );
    final orientation = useAppStore().select(
      context,
      (state) => state.orientation,
    );
    final longPressSpeed = useAppStore().select(
      context,
      (state) => state.longPressSpeed,
    );
    final rememberWindowSize = useAppStore().select(
      context,
      (state) => state.rememberWindowSize,
    );
    final seekStepSeconds = useAppStore().select(
      context,
      (state) => state.seekStepSeconds,
    );
    final seekStepLargeSeconds = useAppStore().select(
      context,
      (state) => state.seekStepLargeSeconds,
    );
    final bool autoHideControls = useAppStore().select(
      context,
      (state) => state.autoHideControls,
    );
    final int controlHideDelaySeconds = useAppStore().select(
      context,
      (state) => state.controlHideDelaySeconds,
    );
    final bool pictureInPicture = useAppStore().select(
      context,
      (state) => state.pictureInPicture,
    );

    final orientationLabels = {
      ScreenOrientation.device: t.device,
      ScreenOrientation.landscape: t.landscape,
      ScreenOrientation.portrait: t.portrait,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PanelSection(
          children: [
            SettingRow(
              icon: Icons.touch_app_rounded,
              label: t.long_press_speed,
              value: '${longPressSpeed}X',
              onTap: () =>
                  showLongPressSpeedDialog(context, value: longPressSpeed),
            ),
            SettingRow(
              icon: Icons.fast_forward_rounded,
              label: t.seek_step,
              value: t.seek_step_seconds(seekStepSeconds),
              onTap: () => showSeekStepDialog(
                context,
                title: t.seek_step,
                value: seekStepSeconds,
                options: const [1, 3, 5, 10, 15, 30, 60],
                onChanged: (value) => useAppStore().updateSeekStep(value),
              ),
            ),
            SettingRow(
              icon: Icons.fast_rewind_rounded,
              label: t.seek_step_large,
              value: t.seek_step_seconds(seekStepLargeSeconds),
              onTap: () => showSeekStepDialog(
                context,
                title: t.seek_step_large,
                value: seekStepLargeSeconds,
                options: const [10, 15, 30, 60, 120, 300],
                onChanged: (value) => useAppStore().updateSeekStepLarge(value),
              ),
            ),
            SettingRow(
              icon: Icons.visibility_off_rounded,
              label: t.auto_hide_controls,
              toggle: autoHideControls,
              onToggle: (_) => useAppStore().toggleAutoHideControls(),
            ),
            SettingRow(
              icon: Icons.timer_outlined,
              label: t.auto_hide_delay,
              value: t.seek_step_seconds(controlHideDelaySeconds),
              enabled: autoHideControls,
              onTap: () => showSeekStepDialog(
                context,
                title: t.auto_hide_delay,
                value: controlHideDelaySeconds,
                options: const [2, 3, 5, 10, 15, 30],
                onChanged: (value) =>
                    useAppStore().updateControlHideDelay(value),
              ),
            ),
            // 画中画: 能力不支持时整项不出现 (Android < 8.0 / iOS),
            // 而不是留一个点了没反应的开关。
            if (PictureInPicture.isSupported)
              SettingRow(
                icon: Icons.picture_in_picture_alt_rounded,
                label: t.picture_in_picture,
                toggle: pictureInPicture,
                onToggle: (_) => useAppStore().togglePictureInPicture(),
              ),
            SettingRow(
              icon: Icons.restart_alt_rounded,
              label: t.always_play_from_beginning,
              toggle: alwaysPlayFromBeginning,
              onToggle: (_) => useAppStore().toggleAlwaysPlayFromBeginning(),
            ),
          ],
        ),
        if (isDesktop)
          PanelSection(
            children: [
              SettingRow(
                icon: Icons.aspect_ratio_rounded,
                label: t.auto_resize,
                toggle: autoResize,
                onToggle: (_) => useAppStore().toggleAutoResize(),
              ),
              SettingRow(
                icon: Icons.photo_size_select_large_rounded,
                label: t.remember_window_size,
                toggle: rememberWindowSize,
                onToggle: (_) => useAppStore().toggleRememberWindowSize(),
              ),
            ],
          ),
        if (Platform.isAndroid || Platform.isIOS)
          PanelSection(
            children: [
              SettingRow(
                icon: Icons.screen_rotation_rounded,
                label: t.screen_orientation,
                value: orientationLabels[orientation] ?? orientation.name,
                onTap: () => showOrientationDialog(context, value: orientation),
              ),
            ],
          ),
      ],
    );
  }
}
