import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/progress.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_history_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/utils/format_date_time.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/playback_progress.dart';
import 'package:iris/widgets/media_row.dart';
import 'package:iris/widgets/panel.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class History extends HookWidget {
  const History({super.key});

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final Map<String, Progress> history = useHistoryStore().select(
      context,
      (state) => state.history,
    );

    final List<MapEntry<String, Progress>> historyList = useMemoized(() {
      final entries = history.entries.toList();
      entries.sort((a, b) => b.value.dateTime.compareTo(a.value.dateTime));
      return entries.sublist(0, min(entries.length, 100));
    }, [history]);

    Future<void> play(int index) async {
      await useAppStore().updateAutoPlay(true);

      final playQueue = historyList
          .asMap()
          .map(
            (index, entry) => MapEntry(
              index,
              PlayQueueItem(file: entry.value.file, index: index),
            ),
          )
          .values
          .toList();

      usePlayQueueStore().update(playQueue: playQueue, index: index);
    }

    return Column(
      children: [
        PanelHeader(
          title: Text(t.history),
          actions: [
            if (historyList.isNotEmpty)
              IconButton(
                tooltip: t.clear_history,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_sweep_rounded, size: 20),
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(t.clear_history),
                      content: Text(t.clear_history_confirm),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(t.cancel),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(t.ok),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await useHistoryStore().clear();
                  }
                },
              ),
          ],
        ),
        const PanelDivider(),
        Expanded(
          child: historyList.isEmpty
              ? PanelEmpty(label: t.history_empty)
              : ScrollablePositionedList.builder(
                  itemCount: historyList.length,
                  itemBuilder: (context, index) {
                    final entry = historyList[index].value;

                    return MediaRow(
                      icon: entry.file.type == ContentType.audio
                          ? Icons.audiotrack_rounded
                          : Icons.movie_rounded,
                      title: entry.file.name,
                      meta: formatShortDateTime(entry.dateTime),
                      progress: playbackProgressLabel(entry),
                      menu: PopupMenuButton<FileOptions>(
                        clipBehavior: Clip.hardEdge,
                        constraints: const BoxConstraints(minWidth: 200),
                        onSelected: (value) async {
                          switch (value) {
                            case FileOptions.addToPlayQueue:
                              usePlayQueueStore().add([entry.file]);
                              break;
                            case FileOptions.remove:
                              useHistoryStore().remove(
                                historyList[index].value,
                              );
                              break;
                            case FileOptions.openInFolder:
                              await openInFolder(context, entry.file);
                              break;
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: FileOptions.addToPlayQueue,
                            child: Text(t.add_to_play_queue),
                          ),
                          PopupMenuItem(
                            value: FileOptions.remove,
                            child: Text(t.remove),
                          ),
                          if (entry.file.path.isNotEmpty)
                            PopupMenuItem(
                              value: FileOptions.openInFolder,
                              child: Text(t.open_in_folder),
                            ),
                        ],
                      ),
                      onTap: () {
                        play(index);
                        Navigator.of(context).pop();
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}
