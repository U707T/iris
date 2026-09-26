import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/l10n/languages.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';

Future<void> showLanguageDialog(BuildContext context) async =>
    await showDialog<void>(
      context: context,
      builder: (context) => const LanguageDialog(),
    );

class LanguageDialog extends HookWidget {
  const LanguageDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final String language =
        useAppStore().select(context, (state) => state.language);

    void updateLanguage(String? newLanguage) {
      if (newLanguage == null) return;
      useAppStore().updateLanguage(newLanguage);
      Navigator.pop(context);
    }

    final Map<String, String> languageOptions = {
      'system': t.system,
      ...languages,
    };

    return AlertDialog(
      title: Text(t.select_language),
      content: SingleChildScrollView(
        child: RadioGroup<String>(
          groupValue: language,
          onChanged: updateLanguage,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: languageOptions.entries.map((entry) {
              final String langCode = entry.key;
              final String langName = entry.value;

              return ListTile(
                title: Text(langName),
                leading: Radio<String>(
                  value: langCode,
                ),
                onTap: () => updateLanguage(langCode),
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
