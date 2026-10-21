import 'dart:io';
import 'package:android_x_storage/android_x_storage.dart';
import 'package:disks_desktop/disks_desktop.dart';
import 'package:drives_windows/drives_windows.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/models/store/play_queue_state.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/utils/files_sort.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/utils/path_conv.dart';
import 'package:iris/utils/platform.dart';
import 'package:path/path.dart' as p;
import 'package:iris/models/file.dart';
import 'package:iris/utils/check_content_type.dart';
import 'package:saf_util/saf_util.dart';

Future<List<LocalStorage>> getLocalStorages(
  BuildContext context,
) async {
  final t = getLocalizations(context);
  if (isDesktop) {
    List<LocalStorage> storages = [];

    if (isWindows) {
      final drivesWindows = DrivesWindows();
      final drives = drivesWindows.getDrives();
      final networkShortcuts = drivesWindows.getNetworkShortcuts();

      for (var drive in drives) {
        if (drive.type == DriveType.noRootDirectory) continue;

        final type = drive.type == DriveType.network
            ? StorageType.network
            : StorageType.internal;
        final name = drive.volumeLabel != null
            ? '${drive.volumeLabel} (${drive.name})'
            : '${drive.type == DriveType.network ? t.network_storage : t.local_storage} (${drive.name})';
        final root = drive.root.replaceAll('\\', '');

        final storage = LocalStorage(
          type: type,
          name: name,
          basePath: [root],
        );

        storages.add(storage);
      }

      for (var shortcut in networkShortcuts) {
        if (shortcut.target == null) continue;
        final storage = LocalStorage(
          type: StorageType.network,
          name: shortcut.name,
          basePath: [shortcut.target!],
        );

        storages.add(storage);
      }
    } else {
      final repository = DisksRepository();
      final disks = await repository.query;
      List<LocalStorage> storages = [];

      for (var disk in disks) {
        for (var mountpoint in disk.mountpoints) {
          final storage = LocalStorage(
            type: StorageType.internal,
            name:
                '${t.local_storage} (${mountpoint.path.replaceAll('\\', '')})',
            basePath: [mountpoint.path.replaceAll('\\', '')],
          );

          storages.add(storage);
        }
      }
    }

    return storages;
  } else if (isAndroid) {
    final androidXStorage = AndroidXStorage();
    final external =
        await androidXStorage.getExternalStorageDirectory().catchError((error) {
      logger('Error getting external storage: $error');
      return null;
    });
    final sdcard =
        await androidXStorage.getSDCardStorageDirectory().catchError((error) {
      logger('Error getting SD card: $error');
      return null;
    });
    final usbs =
        await androidXStorage.getUSBStorageDirectories().catchError((error) {
      logger('Error getting USB storages: $error');
      return <String?>[];
    });

    List<LocalStorage> storages = [];

    if (external != null) {
      final storage = LocalStorage(
        type: StorageType.internal,
        name: t.local_storage,
        basePath: [external],
      );

      storages.add(storage);
    }

    if (sdcard != null) {
      final storage = LocalStorage(
        type: StorageType.sdcard,
        name: 'SD Card',
        basePath: [sdcard],
      );

      storages.add(storage);
    }

    for (var usb in usbs) {
      if (usb != null) {
        final storage = LocalStorage(
          type: StorageType.usb,
          name: t.usb_storage,
          basePath: [usb],
        );

        storages.add(storage);
      }
    }

    return storages;
  }
  return [];
}

Future<PlayQueueState?> getLocalPlayQueue(String filePath) async {
  // 相对路径（终端里 `iris movie.mp4`）先解析成绝对路径:
  // 否则 dirPath 为空, Directory('') 不存在 -> 队列为空 -> 什么都不播。
  final resolvedPath = p.normalize(p.absolute(filePath));
  final type = checkContentType(resolvedPath);

  if (type != ContentType.video && type != ContentType.audio) {
    return null;
  }

  final convedPath = pathConv(resolvedPath);

  final dirPath = convedPath.sublist(0, convedPath.length - 1);
  final files = await LocalStorage(
    type: StorageType.internal,
    name: convedPath.last,
    basePath: dirPath,
  ).getFiles(dirPath);
  final List<FileItem> sortedFiles = filesSort(
    files: files,
    // 跟文件浏览器用同一套排序: 否则"按修改时间/大小"排序的目录,
    // 从 picker / 拖放 / 命令行打开后, 下一条会按文件名跳。
    sortBy: useAppStore().state.sortBy,
    sortOrder: useAppStore().state.sortOrder,
    folderFirst: useAppStore().state.folderFirst,
  );
  final List<FileItem> filteredFiles = sortedFiles
      .where(
          (file) => [ContentType.video, ContentType.audio].contains(file.type))
      .toList();

  final List<PlayQueueItem> playQueue = filteredFiles
      .asMap()
      .entries
      .map((entry) => PlayQueueItem(file: entry.value, index: entry.key))
      .toList();

  final clickedIndex =
      filteredFiles.indexWhere((file) => file.uri == resolvedPath);

  final index = clickedIndex < 0 ? 0 : clickedIndex;
  return PlayQueueState(
    playQueue: playQueue,
    currentIndex: index < 0 || index >= playQueue.length ? 0 : index,
  );
}

Future<void> pickLocalFile() async {
  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: [...Formats.video, ...Formats.audio],
  );

  final filePath = files.isEmpty ? null : files.first.path;

  if (filePath != null) {
    final playQueue = await getLocalPlayQueue(filePath);

    if (playQueue == null || playQueue.playQueue.isEmpty) return;

    await useAppStore().updateAutoPlay(true);
    await usePlayQueueStore().update(
      playQueue: playQueue.playQueue,
      index: playQueue.currentIndex,
    );
  }
}

Future<List<FileItem>> getLocalFiles(
    LocalStorage storage, List<String> path) async {
  final directoryPath = p.joinAll(path);
  final directory = Directory(directoryPath);

  if (!await directory.exists()) {
    logger('Error: Directory does not exist at $directoryPath');
    return [];
  }

  final allEntities = await directory.list().toList();

  Future<FileItem?> toItem(FileSystemEntity entity) async {
    final name = p.basename(entity.path);
    final isDir = entity is Directory;

    try {
      // 单个条目读不到 (坏软链接 / 权限 / 文件被占用) 不应让整个目录失败:
      // 跳过它, 其余文件照常显示。
      final stat = await entity.stat();
      return FileItem(
        storageId: storage.id,
        storageType: storage.type,
        name: name,
        uri: entity.path,
        path: [...path, name],
        isDir: isDir,
        size: isDir ? 0 : stat.size,
        lastModified: stat.modified,
        type: isDir ? ContentType.other : checkContentType(entity.path),
      );
    } catch (e) {
      logger('Skipping unreadable directory entry ${entity.path}: $e');
      return null;
    }
  }

  // stat 是 I/O: 小批量并发, 既不串行等 N 次, 也不会一次打爆网络盘。
  const int chunkSize = 16;
  final List<FileItem> fileItems = [];
  for (var start = 0; start < allEntities.length; start += chunkSize) {
    final end = start + chunkSize < allEntities.length
        ? start + chunkSize
        : allEntities.length;
    final chunk = allEntities.sublist(start, end);
    final items = await Future.wait(chunk.map(toItem));
    fileItems.addAll(items.whereType<FileItem>());
  }

  return fileItems;
}

Future<void> pickContentFile() async {
  final file = await SafUtil().pickFile(mimeTypes: ['video/*', 'audio/*']);
  if (file != null) {
    await useAppStore().updateAutoPlay(true);
    await usePlayQueueStore().update(
      playQueue: [
        PlayQueueItem(
          file: FileItem(
            name: file.name,
            uri: file.uri,
            size: file.length,
          ),
          index: 0,
        ),
      ],
      index: 0,
    );
  }
}

Future<List<FileItem>> getContentFiles(String uri) async {
  final files = await SafUtil().list(uri);

  List<FileItem> fileItems = [];

  for (final file in files) {
    fileItems.add(FileItem(
      name: file.name,
      uri: file.uri,
      path: [uri, file.name],
      isDir: file.isDir,
      size: file.isDir ? 0 : file.length,
      lastModified: DateTime.fromMillisecondsSinceEpoch(file.lastModified),
      type: file.isDir ? ContentType.other : checkContentType(file.name),
    ));
  }

  return fileItems;
}
