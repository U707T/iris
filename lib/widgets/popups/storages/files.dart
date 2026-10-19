import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/globals.dart' as globals;
import 'package:iris/models/file.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/store/use_storage_store.dart';
import 'package:iris/utils/files_sort.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/request_storage_permission.dart';
import 'package:iris/widgets/popups/storages/files_bottom_bar.dart';
import 'package:iris/widgets/popups/storages/files_list_row.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// 文件浏览面板: 列表主体 + 底部工具条 (见 `files_list_row.dart` /
/// `files_bottom_bar.dart`)。
class Files extends HookWidget {
  const Files({super.key, required this.storage});

  final Storage storage;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);

    final refreshState = useState(false);
    void refresh() => refreshState.value = !refreshState.value;

    // 用户去系统设置授权后回到应用: 自动复查权限状态并刷新列表
    // (只在"确实去过后台"后刷新, 避免每次打开面板都多请求一次网络存储)
    final wentBackground = useRef(false);
    final appLifecycleState = useAppLifecycleState();
    useEffect(() {
      if (appLifecycleState != AppLifecycleState.resumed) {
        wentBackground.value = true;
        return null;
      }
      if (!wentBackground.value) return null;
      wentBackground.value = false;
      if (Platform.isAndroid) {
        () async {
          await getStoragePermissionStatus();
          refresh();
        }();
      }
      return null;
    }, [appLifecycleState]);

    final sortBy = useAppStore().select(context, (state) => state.sortBy);
    final sortOrder = useAppStore().select(context, (state) => state.sortOrder);
    final folderFirst =
        useAppStore().select(context, (state) => state.folderFirst);

    final currentPath =
        useStorageStore().select(context, (state) => state.currentPath);

    useEffect(() {
      if (currentPath.isEmpty) {
        useStorageStore().updateCurrentPath(storage.basePath);
      }
      return null;
    }, []);

    final getFiles = useMemoized(
        () async => await storage.getFiles(currentPath),
        [currentPath, refreshState.value]);

    final result = useFuture(getFiles);
    final isLoading = useMemoized(
        () => result.connectionState == ConnectionState.waiting,
        [result.connectionState]);
    final isError = result.error != null;

    final filteredFiles = useMemoized(
        () => (result.data ?? [])
            .where((file) =>
                [ContentType.video, ContentType.audio].contains(file.type) ||
                file.isDir)
            .toList(),
        [result.data]);

    final files = useMemoized(
        () => filesSort(
              files: filteredFiles,
              sortBy: sortBy,
              sortOrder: sortOrder,
              folderFirst: folderFirst,
            ),
        [filteredFiles, sortBy, sortOrder, folderFirst]);

    final itemScrollController = useMemoized(() => ItemScrollController(), []);
    final scrollOffsetController =
        useMemoized(() => ScrollOffsetController(), []);
    final itemPositionsListener = useMemoized(() => ItemPositionsListener.create(), []);
    final scrollOffsetListener =
        useMemoized(() => ScrollOffsetListener.create(), []);

    void play(List<FileItem> files, int index) async {
      final clickedFile = files[index];
      final List<FileItem> filteredFiles = files
          .where((file) =>
              [ContentType.video, ContentType.audio].contains(file.type))
          .toList();

      final List<PlayQueueItem> playQueue = filteredFiles
          .asMap()
          .entries
          .map((entry) => PlayQueueItem(file: entry.value, index: entry.key))
          .toList();
      final newIndex = filteredFiles.indexOf(clickedFile);

      await useAppStore().updateAutoPlay(true);
      await useAppStore().updateShuffle(false);
      await usePlayQueueStore().update(playQueue: playQueue, index: newIndex);
    }

    void back() {
      if (currentPath.length > storage.basePath.length) {
        useStorageStore()
            .updateCurrentPath(currentPath.sublist(0, currentPath.length - 1));
      } else {
        useStorageStore().updateCurrentStorage(null);
        useStorageStore().updateCurrentPath([]);
      }
    }

    /// 列表主体: 依次短路 (权限 → 加载中 → 出错 → 空 → 列表), 避免深层嵌套
    Widget buildFiles() {
      if (Platform.isAndroid &&
          globals.storagePermissionStatus != PermissionStatus.granted &&
          storage is LocalStorage) {
        // 已永久拒绝时 request() 不会再弹框, 只能引导去系统设置
        final permanentlyDenied =
            globals.storagePermissionStatus?.isPermanentlyDenied ?? false;
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t.storage_permission_hint,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () async {
                    if (permanentlyDenied) {
                      await openStoragePermissionSettings();
                    } else {
                      await requestStoragePermission();
                      refresh();
                    }
                  },
                  icon: Icon(permanentlyDenied
                      ? Icons.settings_rounded
                      : Icons.folder_open_rounded),
                  label: Text(permanentlyDenied
                      ? t.open_settings
                      : t.grant_storage_permission),
                ),
              ],
            ),
          ),
        );
      }
      if (isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (isError) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t.unable_to_fetch_files),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: refresh,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(t.retry),
              ),
            ],
          ),
        );
      }
      if (files.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              t.no_media_files,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      }
      return Card(
        color: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: ScrollablePositionedList.builder(
          itemScrollController: itemScrollController,
          scrollOffsetController: scrollOffsetController,
          itemPositionsListener: itemPositionsListener,
          scrollOffsetListener: scrollOffsetListener,
          itemCount: files.length,
          itemBuilder: (context, index) => FilesListRow(
            file: files[index],
            onAddToPlayQueue: () => usePlayQueueStore().add([files[index]]),
            onTap: () {
              if (files[index].isDir == true &&
                  files[index].name.isNotEmpty) {
                useStorageStore().updateCurrentPath(
                    [...currentPath, files[index].name]);
              } else {
                if (files[index].type == ContentType.video ||
                    files[index].type == ContentType.audio) {
                  play(files, index);
                  Navigator.pop(context);
                }
              }
            },
          ),
        ),
      );
    }

    return PopScope(
      // Android 返回手势: 在子目录时先返回上一级, 在存储根目录时返回存储列表
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        back();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: buildFiles()),
          FilesBottomBar(
            storage: storage,
            currentPath: currentPath,
            onBack: back,
            onRefresh: refresh,
          ),
        ],
      ),
    );
  }
}
