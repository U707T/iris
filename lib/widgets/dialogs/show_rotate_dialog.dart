import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/store/player_ui_state.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:iris/utils/get_localizations.dart';

Future<void> showRotateDialog(BuildContext context) async =>
    await showDialog<void>(
      context: context,
      builder: (context) => const RotateDialog(),
    );

class RotateDialog extends HookWidget {
  const RotateDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final rotateMode =
        usePlayerUiStore().select(context, (state) => state.rotateMode);

    final options = <(RotateMode, IconData, String)>[
      (RotateMode.none, Icons.crop_free_rounded, t.rotate_none),
      (RotateMode.rotate90, Icons.rotate_left_rounded, t.rotate_90),
      (RotateMode.rotate180, Icons.rotate_90_degrees_ccw_rounded, t.rotate_180),
      (RotateMode.rotate270, Icons.rotate_right_rounded, t.rotate_270),
      (RotateMode.flipH, Icons.flip_rounded, t.flip_horizontal),
      (RotateMode.flipV, Icons.flip_rounded, t.flip_vertical),
    ];

    return AlertDialog(
      title: Text(t.rotate),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((option) {
            final (mode, icon, label) = option;
            final selected = rotateMode == mode;
            return ListTile(
              leading: Transform.rotate(
                angle: mode == RotateMode.flipV ? 1.5708 : 0,
                child: Icon(
                  icon,
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
              ),
              title: Text(
                label,
                style: selected
                    ? TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : null,
              ),
              trailing: selected ? const Icon(Icons.check_rounded) : null,
              onTap: () {
                usePlayerUiStore().updateRotateMode(mode);
                Navigator.pop(context);
              },
            );
          }).toList(),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () {
            usePlayerUiStore().resetRotate();
            Navigator.pop(context);
          },
          child: Text(t.reset),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.cancel),
        ),
      ],
    );
  }
}
