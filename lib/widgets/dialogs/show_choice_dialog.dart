import 'package:material_ui/material_ui.dart';
import 'package:iris/globals.dart' show longPressSpeedStops, speedStops;
import 'package:iris/l10n/languages.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';

/// 一个选项：值 + 显示文字。
class Choice<T> {
  const Choice(this.value, this.label);

  final T value;
  final String label;
}

/// 所有「从一组里选一个」的对话框。
///
/// 以前是五个几乎一样的文件：语言、主题、长按倍速、屏幕方向、倍速，每个都
/// 自带一份 AlertDialog + Radio 列表 + 取消按钮。选中即生效、对话框随即关闭，
/// 取消按钮从来没被点过；左侧的圆圈又把「当前值」挤到了第二视觉层。
///
/// 现在只有这一份：列表 + 右侧对勾，选中就关。没有取消按钮 —— 点外面就是取消。
Future<void> showChoiceDialog<T>(
  BuildContext context, {
  required String title,
  required List<Choice<T>> choices,
  required T value,
  required ValueChanged<T> onChanged,
}) async {
  await showDialog<void>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;

      return AlertDialog(
        title: Text(title),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320, maxHeight: 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final choice in choices)
                  ListTile(
                    selected: choice.value == value,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    title: Text(choice.label),
                    trailing: choice.value == value
                        ? Icon(
                            Icons.check_rounded,
                            size: 20,
                            color: scheme.primary,
                          )
                        : null,
                    onTap: () {
                      onChanged(choice.value);
                      Navigator.of(context).pop();
                    },
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Future<void> showLanguageDialog(BuildContext context, {required String value}) {
  final t = getLocalizations(context);
  return showChoiceDialog<String>(
    context,
    title: t.select_language,
    value: value,
    choices: [
      Choice('system', t.system),
      for (final entry in languages.entries) Choice(entry.key, entry.value),
    ],
    onChanged: (language) => useAppStore().updateLanguage(language),
  );
}

Future<void> showThemeModeDialog(
  BuildContext context, {
  required ThemeMode value,
}) {
  final t = getLocalizations(context);
  return showChoiceDialog<ThemeMode>(
    context,
    title: t.theme_mode,
    value: value,
    choices: [
      Choice(ThemeMode.system, t.system),
      Choice(ThemeMode.light, t.light),
      Choice(ThemeMode.dark, t.dark),
    ],
    onChanged: (mode) => useAppStore().updateThemeMode(mode),
  );
}

Future<void> showLongPressSpeedDialog(
  BuildContext context, {
  required double value,
}) {
  final t = getLocalizations(context);
  return showChoiceDialog<double>(
    context,
    title: t.long_press_speed,
    value: value,
    choices: [
      for (final speed in longPressSpeedStops) Choice(speed, '${speed}X'),
    ],
    onChanged: (speed) => useAppStore().updateLongPressSpeed(speed),
  );
}

Future<void> showOrientationDialog(
  BuildContext context, {
  required ScreenOrientation value,
}) {
  final t = getLocalizations(context);
  final labels = {
    ScreenOrientation.device: t.device,
    ScreenOrientation.landscape: t.landscape,
    ScreenOrientation.portrait: t.portrait,
  };
  return showChoiceDialog<ScreenOrientation>(
    context,
    title: t.screen_orientation,
    value: value,
    choices: [
      for (final orientation in ScreenOrientation.values)
        Choice(orientation, labels[orientation] ?? orientation.name),
    ],
    onChanged: (orientation) => useAppStore().updateOrientation(orientation),
  );
}

Future<void> showRateDialog(BuildContext context, {required double value}) {
  final t = getLocalizations(context);
  return showChoiceDialog<double>(
    context,
    title: t.playback_speed,
    value: value,
    choices: [for (final rate in speedStops) Choice(rate, '${rate}X')],
    onChanged: (rate) => useAppStore().updateRate(rate),
  );
}

Future<void> showSeekStepDialog(
  BuildContext context, {
  required String title,
  required int value,
  required List<int> options,
  required ValueChanged<int> onChanged,
}) {
  final t = getLocalizations(context);
  return showChoiceDialog<int>(
    context,
    title: title,
    value: value,
    choices: [
      for (final seconds in options)
        Choice(seconds, t.seek_step_seconds(seconds)),
    ],
    onChanged: onChanged,
  );
}
