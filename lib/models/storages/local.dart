import 'dart:async';
import 'dart:io';

import 'package:android_x_storage/android_x_storage.dart';
import 'package:disks_desktop/disks_desktop.dart';
import 'package:drives_windows/drives_windows.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:iris/models/storages/directory_scan.dart';
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

Future<List<LocalStorage>> getLocalStorages(BuildContext context) async {
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

        final storage = LocalStorage(type: type, name: name, basePath: [root]);

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
    final external = await androidXStorage
        .getExternalStorageDirectory()
        .catchError((error) {
          logger('Error getting external storage: $error');
          return null;
        });
    final sdcard = await androidXStorage.getSDCardStorageDirectory().catchError(
      (error) {
        logger('Error getting SD card: $error');
        return null;
      },
    );
    final usbs = await androidXStorage.getUSBStorageDirectories().catchError((
      error,
    ) {
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
  ).getFiles(dirPath, mediaOnly: true);
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
        (file) => [ContentType.video, ContentType.audio].contains(file.type),
      )
      .toList();

  final List<PlayQueueItem> playQueue = filteredFiles
      .asMap()
      .entries
      .map((entry) => PlayQueueItem(file: entry.value, index: entry.key))
      .toList();

  final clickedIndex = filteredFiles.indexWhere(
    (file) => file.uri == resolvedPath,
  );

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
  LocalStorage storage,
  List<String> path, {
  bool mediaOnly = false,
  DirectoryScan? scan,
}) async {
  if (scan?.isCancelled == true) return [];
  final directoryPath = p.joinAll(path);
  final directory = Directory(directoryPath);
  final exists = await directory.exists();
  if (scan?.isCancelled == true) return [];
  if (!exists) {
    logger('Error: Directory does not exist at $directoryPath');
    return [];
  }

  return scanLocalDirectoryEntries(
    storage,
    path,
    directory.list(),
    mediaOnly: mediaOnly,
    scan: scan,
  );
}

Future<List<FileItem>> scanLocalDirectoryEntries(
  LocalStorage storage,
  List<String> path,
  Stream<FileSystemEntity> entries, {
  bool mediaOnly = false,
  DirectoryScan? scan,
}) async {
  if (scan?.isCancelled == true) return [];

  Future<FileItem?> toItem(
    FileSystemEntity entity,
    String name,
    bool isDir,
    ContentType type,
  ) async {
    try {
      // 单个条目读不到时仍显示其余条目。
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
        type: type,
      );
    } catch (e) {
      logger('Skipping unreadable directory entry ${entity.path}: $e');
      return null;
    }
  }

  const batchSize = 16;
  final fileItems = <FileItem>[];
  final batch = <Future<FileItem?>>[];
  final iterator = StreamIterator(entries);
  final unregister = scan?.onCancel(() {
    unawaited(
      iterator.cancel().catchError((Object error) {
        logger('Unable to cancel directory enumeration: $error');
      }),
    );
  });
  try {
    while (scan?.isCancelled != true && await iterator.moveNext()) {
      if (scan?.isCancelled == true) break;
      final entry = iterator.current;
      final name = p.basename(entry.path);
      final isDir = entry is Directory;
      final type = isDir ? ContentType.other : checkContentType(name);
      if (mediaOnly &&
          !isDir &&
          type != ContentType.video &&
          type != ContentType.audio) {
        continue;
      }
      batch.add(toItem(entry, name, isDir, type));
      if (batch.length == batchSize) {
        fileItems.addAll((await Future.wait(batch)).whereType<FileItem>());
        batch.clear();
      }
    }
    if (scan?.isCancelled == true) return [];
    fileItems.addAll((await Future.wait(batch)).whereType<FileItem>());
    return scan?.isCancelled == true ? [] : fileItems;
  } finally {
    unregister?.call();
    await iterator.cancel();
  }
}

Future<void> pickContentFile() async {
  final file = await SafUtil().pickFile(mimeTypes: ['video/*', 'audio/*']);
  if (file != null) {
    await useAppStore().updateAutoPlay(true);
    await usePlayQueueStore().update(
      playQueue: [
        PlayQueueItem(
          file: FileItem(name: file.name, uri: file.uri, size: file.length),
          index: 0,
        ),
      ],
      index: 0,
    );
  }
}

Future<List<FileItem>> getContentFiles(
  String uri, {
  bool mediaOnly = false,
  DirectoryScan? scan,
}) async {
  if (scan?.isCancelled == true) return [];
  // SafUtil.list uses a single platform-channel call with no abort API.
  final files = await SafUtil().list(uri);
  if (scan?.isCancelled == true) return [];

  final fileItems = <FileItem>[];
  for (final file in files) {
    final type = file.isDir ? ContentType.other : checkContentType(file.name);
    if (mediaOnly &&
        !file.isDir &&
        type != ContentType.video &&
        type != ContentType.audio) {
      continue;
    }
    fileItems.add(
      FileItem(
        name: file.name,
        uri: file.uri,
        path: [uri, file.name],
        isDir: file.isDir,
        size: file.isDir ? 0 : file.length,
        lastModified: DateTime.fromMillisecondsSinceEpoch(file.lastModified),
        type: type,
      ),
    );
  }

  return fileItems;
}
