import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/globals.dart' show longPressSpeedStops;
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';

Future<void> showLongPressSpeedDialog(BuildContext context) async =>
    await showDialog<void>(
      context: context,
      builder: (context) => const LongPressSpeedDialog(),
    );

class LongPressSpeedDialog extends HookWidget {
  const LongPressSpeedDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final longPressSpeed =
        useAppStore().select(context, (state) => state.longPressSpeed);

    void updateSpeed(double? newSpeed) {
      if (newSpeed == null) return;
      useAppStore().updateLongPressSpeed(newSpeed);
      Navigator.pop(context);
    }

    return AlertDialog(
      title: Text(t.long_press_speed),
      content: SingleChildScrollView(
        child: RadioGroup<double>(
          groupValue: longPressSpeed,
          onChanged: updateSpeed,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: longPressSpeedStops.map((item) {
              return ListTile(
                title: Text('${item}X'),
                leading: Radio<double>(
                  value: item,
                ),
                onTap: () => updateSpeed(item),
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
