import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/l10n/languages.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/dialogs/show_choice_dialog.dart';
import 'package:iris/widgets/panel.dart';
import 'package:iris/widgets/setting_row.dart';

class General extends HookWidget {
  const General({super.key});

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);

    final language = useAppStore().select(context, (state) => state.language);
    final themeMode = useAppStore().select(context, (state) => state.themeMode);
    final pureBlackTheme = useAppStore().select(
      context,
      (state) => state.pureBlackTheme,
    );

    final languageLabel = language == 'system'
        ? t.system
        : languages[language] ?? language;
    final themeLabel = switch (themeMode) {
      ThemeMode.system => t.system,
      ThemeMode.light => t.light,
      ThemeMode.dark => t.dark,
    };

    return PanelSection(
      children: [
        SettingRow(
          icon: Icons.translate_rounded,
          label: t.language,
          value: languageLabel,
          onTap: () => showLanguageDialog(context, value: language),
        ),
        SettingRow(
          icon: themeMode == ThemeMode.light
              ? Icons.light_mode_rounded
              : themeMode == ThemeMode.dark
              ? Icons.dark_mode_rounded
              : Icons.contrast_rounded,
          label: t.theme_mode,
          value: themeLabel,
          onTap: () => showThemeModeDialog(context, value: themeMode),
        ),
        if (themeMode != ThemeMode.light)
          SettingRow(
            icon: Icons.contrast_rounded,
            label: t.pure_black_theme,
            toggle: pureBlackTheme,
            onToggle: (_) => useAppStore().togglePureBlackTheme(),
          ),
      ],
    );
  }
}
