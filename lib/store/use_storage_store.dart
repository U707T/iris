import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/models/store/storage_state.dart';
import 'package:iris/store/persistent_store.dart';
import 'package:iris/utils/logger.dart';

class StorageStore extends PersistentStore<StorageState> {
  StorageStore() : super(StorageState());

  Storage? findById(String id) =>
      state.storages.firstWhereOrNull((storage) => storage.id == id);

  Future<void> addStorage(Storage storage) async {
    set(state.copyWith(storages: [...state.storages, storage]));
    await save(state);
  }

  Future<void> updateStorage(int index, Storage storage) async {
    if (index < 0 || index >= state.storages.length) {
      return;
    }

    set(state.copyWith(
        storages: [...state.storages]
          ..removeAt(index)
          ..insert(index, storage)));
    await save(state);
  }

  Future<void> removeStorage(Storage storage) async {
    set(state.copyWith(storages: [...state.storages]..remove(storage)));
    await save(state);
  }

  Future<void> addFavorite(Favorite favorite) async {
    set(state.copyWith(favorites: [...state.favorites, favorite]));
    await save(state);
  }

  Future<void> removeFavorite(Favorite favorite) async {
    set(state.copyWith(favorites: [...state.favorites]..remove(favorite)));
    await save(state);
  }

  Future<void> updateCurrentStorage(Storage? storage) async {
    set(state.copyWith(currentStorage: storage));
    await save(state);
  }

  Future<void> updateCurrentPath(List<String> path) async {
    set(state.copyWith(currentPath: path));
    await save(state);
  }

  @override
  Future<StorageState?> load() async {
    logger('Loading StorageState');
    try {
            final storage = FlutterSecureStorage(aOptions: const AndroidOptions());

      String? storageState = await storage.read(key: 'storage_state');
      if (storageState != null) {
        final data = json.decode(storageState);
        if (data is Map<String, dynamic>) {
          _dropRemovedStorageTypes(data);
          return StorageState.fromJson(data);
        }
      }
    } catch (e) {
      logger('Error loading StorageState: $e');
    }
    return null;
  }

  /// 旧版本可能存过已移除的存储类型 (FTP): 直接读会解析失败并丢掉全部存储,
  /// 所以在反序列化前把它们从 JSON 里剔掉 (连同指向它们的收藏 / 当前目录)。
  void _dropRemovedStorageTypes(Map<String, dynamic> data) {
    const removedTypes = {'ftp'};
    final removedIds = <String>{};

    final storages = data['storages'];
    if (storages is List) {
      storages.removeWhere((item) {
        if (item is Map && removedTypes.contains('${item['type']}')) {
          removedIds.add('${item['id']}');
          return true;
        }
        return false;
      });
    }

    final favorites = data['favorites'];
    if (favorites is List) {
      favorites.removeWhere((item) =>
          item is Map && removedIds.contains('${item['storageId']}'));
    }

    final current = data['currentStorage'];
    if (current is Map && removedTypes.contains('${current['type']}')) {
      data['currentStorage'] = null;
      data['currentPath'] = <String>[];
    }
  }

  @override
  Future<void> save(StorageState state) async {
    try {
            final storage = FlutterSecureStorage(aOptions: const AndroidOptions());

      await storage.write(
          key: 'storage_state', value: json.encode(state.toJson()));
    } catch (e) {
      logger('Error saving StorageState: $e');
    }
  }
}

StorageStore useStorageStore() => create(() => StorageStore());
