import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_history_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/utils/file_size_convert.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/playback_progress.dart';
import 'package:iris/widgets/media_row.dart';
import 'package:iris/widgets/panel.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class PlayQueue extends HookWidget {
  const PlayQueue({super.key});

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final playQueue = usePlayQueueStore().select(
      context,
      (state) => state.playQueue,
    );
    final currentIndex = usePlayQueueStore().select(
      context,
      (state) => state.currentIndex,
    );

    final int currentPlayIndex = useMemoized(
      () => playQueue.indexWhere((element) => element.index == currentIndex),
      [playQueue, currentIndex],
    );

    final itemScrollController = useMemoized(() => ItemScrollController(), []);

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (itemScrollController.isAttached && playQueue.isNotEmpty) {
          itemScrollController.jumpTo(
            index: currentPlayIndex - 3 < 0 ? 0 : currentPlayIndex - 1,
          );
        }
      });
      return;
    }, []);

    return Column(
      children: [
        PanelHeader(title: Text(t.play_queue)),
        const PanelDivider(),
        Expanded(
          child: playQueue.isEmpty
              ? PanelEmpty(label: t.queue_empty)
              : ScrollablePositionedList.builder(
                  itemCount: playQueue.length,
                  itemScrollController: itemScrollController,
                  itemBuilder: (context, index) {
                    final item = playQueue[index];
                    final progress = useHistoryStore().findById(
                      item.file.getID(),
                    );

                    return MediaRow(
                      icon: item.file.type == ContentType.audio
                          ? Icons.audiotrack_rounded
                          : Icons.movie_rounded,
                      title: item.file.name,
                      meta: item.file.size > 0
                          ? '${fileSizeConvert(item.file.size)} MB'
                          : null,
                      progress: playbackProgressLabel(progress),
                      selected: currentPlayIndex == index,
                      menu: PopupMenuButton<FileOptions>(
                        clipBehavior: Clip.hardEdge,
                        constraints: const BoxConstraints(minWidth: 200),
                        onSelected: (value) async {
                          switch (value) {
                            case FileOptions.remove:
                              usePlayQueueStore().remove(item);
                              break;
                            case FileOptions.openInFolder:
                              await openInFolder(context, item.file);
                              break;
                            default:
                              break;
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: FileOptions.remove,
                            child: Text(t.remove),
                          ),
                          if (item.file.path.isNotEmpty)
                            PopupMenuItem(
                              value: FileOptions.openInFolder,
                              child: Text(t.open_in_folder),
                            ),
                        ],
                      ),
                      onTap: () async {
                        await useAppStore().updateAutoPlay(true);
                        usePlayQueueStore().updateCurrentIndex(item.index);
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}
