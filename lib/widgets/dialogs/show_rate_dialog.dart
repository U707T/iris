import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/globals.dart' show speedStops;
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';

Future<void> showRateDialog(BuildContext context) async =>
    await showDialog<void>(
      context: context,
      builder: (context) => const RateDialog(),
    );

class RateDialog extends HookWidget {
  const RateDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final rate = useAppStore().select(context, (state) => state.rate);

    void updateRate(double? newRate) {
      if (newRate == null) return;
      useAppStore().updateRate(newRate);
      Navigator.pop(context);
    }

    return AlertDialog(
      title: Text(t.playback_speed),
      content: SingleChildScrollView(
        child: RadioGroup<double>(
          groupValue: rate,
          onChanged: updateRate,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: speedStops.map((item) {
              return ListTile(
                title: Text('${item}X'),
                leading: Radio<double>(
                  value: item,
                ),
                onTap: () => updateRate(item),
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
