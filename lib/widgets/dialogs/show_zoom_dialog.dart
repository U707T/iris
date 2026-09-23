import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/globals.dart' show maxZoom, minZoom, zoomStep;
import 'package:iris/store/use_player_ui_store.dart';
import 'package:iris/utils/get_localizations.dart';

Future<void> showZoomDialog(BuildContext context) async =>
    await showDialog<void>(
      context: context,
      builder: (context) => const ZoomDialog(),
    );

class ZoomDialog extends HookWidget {
  const ZoomDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final zoom = usePlayerUiStore().select(context, (state) => state.zoom);

    void updateZoom(double value) => usePlayerUiStore().updateZoom(value);

    return AlertDialog(
      title: Text('${t.zoom} ${(zoom * 100).round()}%'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 320,
            child: Slider(
              value: zoom,
              min: minZoom,
              max: maxZoom,
              onChanged: updateZoom,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton(
                onPressed: () => updateZoom(zoom - zoomStep),
                child: const Icon(Icons.remove_rounded),
              ),
              TextButton(
                onPressed: () => updateZoom(1.0),
                child: Text(t.reset),
              ),
              TextButton(
                onPressed: () => updateZoom(zoom + zoomStep),
                child: const Icon(Icons.add_rounded),
              ),
            ],
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.ok),
        ),
      ],
    );
  }
}
