import 'package:collection/collection.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/models/store/storage_state.dart';
import 'package:iris/store/persistence/json_persistence.dart';
import 'package:iris/store/persistence/key_value_store.dart';
import 'package:iris/store/persistent_store.dart';
import 'package:iris/store/state_decoders.dart';

class StorageStore extends PersistentStore<StorageState> {
  StorageStore()
      : super(
          StorageState(),
          JsonPersistence<StorageState>(
            // WebDAV 凭据必须继续留在加密存储里。
            store: SecureKeyValueStore.instance,
            key: 'storage_state',
            fromJson: decodeStorageState,
            toJson: (state) => state.toJson(),
          ),
        );

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
  Future<StorageState?> load() => loadPersisted();
}

StorageStore useStorageStore() => create(() => StorageStore());
