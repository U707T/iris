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
      // SAF (content://) 目录走 SafUtil, 不需要「所有文件访问」权限。
      final bool isSafStorage = storage is LocalStorage &&
          storage.basePath.isNotEmpty &&
          storage.basePath.first.startsWith('content://');
      final bool needsStoragePermission = Platform.isAndroid &&
          storage is LocalStorage &&
          !isSafStorage &&
          globals.storagePermissionStatus != PermissionStatus.granted;

      if (needsStoragePermission) {
        return Center(
          child: ElevatedButton(
              onPressed: () async {
                final status = await requestStoragePermission();
                // 永久拒绝后 request() 不会再弹框, 只能把用户送到系统设置。
                if (status.isPermanentlyDenied || status.isRestricted) {
                  await openAppSettings();
                }
                refresh();
              },
              child: Text(t.grant_storage_permission)),
        );
      }
      if (isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (isError) {
        return Center(child: Text(t.unable_to_fetch_files));
      }
      if (files.isEmpty) {
        return const Center();
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
