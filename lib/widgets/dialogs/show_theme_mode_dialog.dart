import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';

Future<void> showThemeModeDialog(BuildContext context) async =>
    await showDialog<void>(
      context: context,
      builder: (context) => const ThemeModeDialog(),
    );

class ThemeModeDialog extends HookWidget {
  const ThemeModeDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final themeMode = useAppStore().select(context, (state) => state.themeMode);

    void updateThemeMode(ThemeMode? newThemeMode) {
      if (newThemeMode == null) return;
      useAppStore().updateThemeMode(newThemeMode);
      Navigator.pop(context);
    }

    final Map<String, ThemeMode> themeOptions = {
      t.system: ThemeMode.system,
      t.light: ThemeMode.light,
      t.dark: ThemeMode.dark,
    };

    return AlertDialog(
      title: Text(t.theme_mode),
      content: SingleChildScrollView(
        child: RadioGroup<ThemeMode>(
          groupValue: themeMode,
          onChanged: updateThemeMode,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: themeOptions.entries.map((entry) {
              final String label = entry.key;
              final ThemeMode value = entry.value;

              return ListTile(
                title: Text(label),
                leading: Radio<ThemeMode>(
                  value: value,
                ),
                onTap: () => updateThemeMode(value),
                contentPadding: const EdgeInsets.only(left: 8),
              );
            }).toList(),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.cancel),
        ),
      ],
    );
  }
}
