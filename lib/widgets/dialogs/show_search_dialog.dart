import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/storages/directory_scan.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/store/use_storage_store.dart';
import 'package:iris/utils/file_size_convert.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/utils/search_files.dart';
import 'package:iris/widgets/media_row.dart';

/// 在当前存储的当前目录中递归搜索媒体文件
Future<void> showSearchDialog(
  BuildContext context, {
  required Storage storage,
}) async => await showDialog<void>(
  context: context,
  builder: (context) => SearchDialog(storage: storage),
);

class SearchDialog extends HookWidget {
  const SearchDialog({super.key, required this.storage});

  final Storage storage;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);

    final currentPath = useStorageStore().select(
      context,
      (state) => state.currentPath,
    );

    final controller = useTextEditingController();
    final isSearching = useState(false);
    final results = useState<List<FileItem>>([]);
    final hasSearched = useState(false);
    final activeScan = useRef<DirectoryScan?>(null);

    useEffect(() {
      return () => activeScan.value?.cancel();
    }, const []);

    Future<void> search() async {
      final keyword = controller.text.trim();
      if (keyword.isEmpty) return;

      activeScan.value?.cancel();
      final scan = DirectoryScan();
      activeScan.value = scan;
      isSearching.value = true;
      hasSearched.value = true;

      List<FileItem> files;
      try {
        files = await searchFiles(
          storage: storage,
          basePath: currentPath,
          query: keyword,
          scan: scan,
        );
      } catch (e) {
        logger('Search failed: $e');
        files = const [];
      }

      if (scan.isCancelled || !context.mounted) return;

      activeScan.value = null;
      results.value = files;
      isSearching.value = false;
    }

    Future<void> play(FileItem file) async {
      final index = results.value.indexOf(file);
      final playQueue = results.value
          .asMap()
          .entries
          .map((entry) => PlayQueueItem(file: entry.value, index: entry.key))
          .toList();

      await useAppStore().updateAutoPlay(true);
      await useAppStore().updateShuffle(false);
      await usePlayQueueStore().update(
        playQueue: playQueue,
        index: index < 0 ? 0 : index,
      );
    }

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.search_rounded, size: 20),
          const SizedBox(width: 8),
          Text(t.search),
        ],
      ),
      content: SizedBox(
        width: 480,
        height: 400,
        child: Column(
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: t.search_hint,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear_rounded),
                  onPressed: () {
                    activeScan.value?.cancel();
                    activeScan.value = null;
                    controller.clear();
                    results.value = [];
                    isSearching.value = false;
                    hasSearched.value = false;
                  },
                ),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => search(),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: isSearching.value
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 12),
                          Text(t.searching),
                        ],
                      ),
                    )
                  : !hasSearched.value
                  ? const Center(child: SizedBox())
                  : results.value.isEmpty
                  ? Center(child: Text(t.no_search_results))
                  : ListView.builder(
                      itemCount: results.value.length,
                      itemBuilder: (context, index) {
                        final file = results.value[index];
                        return MediaRow(
                          icon: file.type == ContentType.audio
                              ? Icons.audiotrack_rounded
                              : Icons.movie_rounded,
                          title: file.name,
                          meta: file.size != 0
                              ? '${fileSizeConvert(file.size)} MB'
                              : null,
                          onTap: () {
                            Navigator.pop(context);
                            play(file);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: <Widget>[FilledButton(onPressed: search, child: Text(t.search))],
    );
  }
}
