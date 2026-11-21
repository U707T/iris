import 'package:collection/collection.dart';
import 'package:material_ui/material_ui.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/storages/directory_scan.dart';
import 'package:iris/models/storages/local.dart';
import 'package:iris/models/storages/webdav.dart';
import 'package:iris/utils/platform.dart';
import 'package:iris/widgets/popup.dart';
import 'package:iris/widgets/popups/storages/storages.dart';
import 'package:iris/store/use_storage_store.dart';

part 'storage.freezed.dart';
part 'storage.g.dart';

const String localStorageId = 'local';

enum StorageType { none, internal, network, usb, sdcard, webdav }

enum StorageOptions { edit, remove }

abstract class _Storage {
  String get id;
  StorageType get type;
  String get name;
  List<String> get basePath;

  Map<String, dynamic> toJson();

  Future<List<FileItem>> getFiles(
    List<String> path, {
    bool mediaOnly = false,
    DirectoryScan? scan,
  });

  String? getAuth();

  String? getAuthForUri(String mediaUri);
}

@freezed
sealed class Storage with _$Storage implements _Storage {
  const Storage._();

  factory Storage.local({
    @Default(localStorageId) String id,
    required StorageType type,
    required String name,
    required List<String> basePath,
  }) = LocalStorage;

  factory Storage.webdav({
    required String id,
    @Default(StorageType.webdav) StorageType type,
    required String name,
    @JsonKey(name: 'url') required String host,
    required List<String> basePath,
    required String port,
    required String username,
    required String password,
    required bool https,
  }) = WebDAVStorage;

  factory Storage.fromJson(Map<String, dynamic> json) =>
      _$StorageFromJson(json);

  @override
  Future<List<FileItem>> getFiles(
    List<String> path, {
    bool mediaOnly = false,
    DirectoryScan? scan,
  }) async {
    if (path.isEmpty || scan?.isCancelled == true) return [];
    switch (type) {
      case StorageType.internal:
      case StorageType.network:
      case StorageType.usb:
      case StorageType.sdcard:
        if (isAndroid && path[0].startsWith('content://')) {
          return getContentFiles(
            path.join('%2F'),
            mediaOnly: mediaOnly,
            scan: scan,
          );
        }
        return getLocalFiles(
          this as LocalStorage,
          path,
          mediaOnly: mediaOnly,
          scan: scan,
        );
      case StorageType.webdav:
        return getWebDAVFiles(
          this as WebDAVStorage,
          path,
          mediaOnly: mediaOnly,
          scan: scan,
        );
      case StorageType.none:
        return [];
    }
  }

  @override
  String? getAuthForUri(String mediaUri) => this is WebDAVStorage
      ? getWebDAVAuthForUri(this as WebDAVStorage, mediaUri)
      : null;

  @override
  String? getAuth() {
    switch (type) {
      case StorageType.webdav:
        return getWebDAVAuth(this as WebDAVStorage);
      default:
        return null;
    }
  }
}

/// Resolve folder browsing without manufacturing a local WebDAV object.
Storage? storageForFileFolder(
  FileItem file,
  List<Storage> configured,
  List<LocalStorage> discovered,
) {
  if (file.path.isEmpty) return null;
  final known = configured.firstWhereOrNull((s) => s.id == file.storageId);
  if (known != null) return known;
  if (file.storageType == StorageType.webdav ||
      Uri.tryParse(file.uri)?.hasAuthority == true &&
          !file.uri.startsWith('content://') &&
          !file.uri.startsWith('file://')) {
    return null;
  }
  return discovered.firstWhereOrNull(
        (s) => s.basePath.isNotEmpty && s.basePath.first == file.path.first,
      ) ??
      LocalStorage(
        type: file.storageType == StorageType.none
            ? StorageType.internal
            : file.storageType,
        name: file.path.first,
        basePath: [file.path.first],
      );
}

Future<void> openInFolder(BuildContext context, FileItem file) async {
  if (file.path.isEmpty) return;
  final store = useStorageStore();
  await store.ready;
  var storage = storageForFileFolder(file, store.state.storages, const []);
  if (storage is LocalStorage) {
    if (!context.mounted) return;
    storage = storageForFileFolder(
      file,
      store.state.storages,
      await getLocalStorages(context),
    );
  }
  // Deleted network connections must be configured again before browsing.
  if (storage == null) return;
  await store.updateCurrentStorage(storage);
  await store.updateCurrentPath(file.path.sublist(0, file.path.length - 1));
  if (context.mounted) {
    replacePopup(
      context: context,
      child: Storages(),
      direction: PopupDirection.right,
    );
  }
}
