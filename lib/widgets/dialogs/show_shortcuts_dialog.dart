import 'package:flutter/material.dart';
import 'package:iris/utils/get_localizations.dart';

Future<void> showShortcutsDialog(BuildContext context) async =>
    await showDialog<void>(
      context: context,
      builder: (context) => const ShortcutsDialog(),
    );

class ShortcutsDialog extends StatelessWidget {
  const ShortcutsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);

    final groups = <(String, List<(String, String)>)>[
      (
        t.playback,
        [
          ('Space', t.play_pause),
          ('← / →', '${t.backward} / ${t.forward} (${t.shift_for_large_step})'),
          ('Ctrl + ← / →', '${t.previous} / ${t.next}'),
          ('S', t.subtitle_and_audio_track),
          ('+ / -', '${t.step_forward} / ${t.step_backward}'),
          ('Ctrl + S', t.screenshot),
          ('Ctrl + T', t.rotate),
          ('Ctrl + R', t.repeat_none.split(':').first),
          ('Ctrl + X', t.shuffle),
        ],
      ),
      (
        t.interface,
        [
          ('Ctrl + V', t.video_zoom),
          ('Ctrl + 滚轮', t.zoom),
          ('Enter / F11', '${t.enter_fullscreen} / ${t.exit_fullscreen}'),
          ('F10', t.always_on_top),
          ('Ctrl + M', t.mute),
          ('Tab', t.menu),
          ('Ctrl + P', t.settings),
          ('Ctrl + H', t.history),
          ('Ctrl + F', t.storage),
          ('P', t.play_queue),
        ],
      ),
      (
        t.troubleshooting,
        [
          ('Ctrl + I', t.playback_stats),
          ('Ctrl + O', t.open_file),
          ('Ctrl + L', t.open_link),
          ('Ctrl + C', t.stop),
          ('Esc', t.back),
          ('Alt + X', t.exit),
        ],
      ),
    ];

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.keyboard_rounded, size: 22),
          const SizedBox(width: 8),
          Text(t.shortcuts),
        ],
      ),
      content: SizedBox(
        width: 460,
        height: 420,
        child: ListView(
          children: [
            for (final (title, items) in groups) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              ...items.map(
                (item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 150,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            item.$1,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Flexible(child: Text(item.$2)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
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
