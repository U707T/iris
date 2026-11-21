import 'package:collection/collection.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/models/store/storage_state.dart';
import 'package:iris/store/persistence/json_persistence.dart';
import 'package:iris/store/persistence/key_value_store.dart';
import 'package:iris/store/persistent_store.dart';
import 'package:iris/store/state_decoders.dart';

class StorageStore extends PersistentStore<StorageState> {
  StorageStore({JsonPersistence<StorageState>? persistence})
    : super(
        StorageState(),
        persistence ??
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
    if (!isLoaded) await ready;
    set(state.copyWith(storages: [...state.storages, storage]));
    await save(state);
  }

  Future<void> updateStorage(int index, Storage storage) async {
    if (!isLoaded) await ready;
    if (index < 0 || index >= state.storages.length) {
      return;
    }

    final previous = state.storages[index];
    set(
      state.copyWith(
        storages: [...state.storages]..[index] = storage,
        currentStorage: state.currentStorage?.id == previous.id
            ? storage
            : state.currentStorage,
        currentPath: state.currentStorage?.id == previous.id
            ? storage.basePath
            : state.currentPath,
      ),
    );
    await save(state);
  }

  Future<void> removeStorage(Storage storage) async {
    if (!isLoaded) await ready;
    set(
      state.copyWith(
        storages: state.storages.where((s) => s.id != storage.id).toList(),
        favorites: state.favorites
            .where((f) => f.storageId != storage.id)
            .toList(),
        currentStorage: state.currentStorage?.id == storage.id
            ? null
            : state.currentStorage,
        currentPath: state.currentStorage?.id == storage.id
            ? const []
            : state.currentPath,
      ),
    );
    await save(state);
  }

  Future<void> addFavorite(Favorite favorite) async {
    if (!isLoaded) await ready;
    set(state.copyWith(favorites: [...state.favorites, favorite]));
    await save(state);
  }

  Future<void> removeFavorite(Favorite favorite) async {
    if (!isLoaded) await ready;
    set(state.copyWith(favorites: [...state.favorites]..remove(favorite)));
    await save(state);
  }

  Future<void> updateCurrentStorage(Storage? storage) async {
    if (!isLoaded) await ready;
    set(state.copyWith(currentStorage: storage));
    await save(state);
  }

  Future<void> updateCurrentPath(List<String> path) async {
    if (!isLoaded) await ready;
    set(state.copyWith(currentPath: path));
    await save(state);
  }

  @override
  Future<StorageState?> load() => loadPersisted();
}

StorageStore useStorageStore() => create(() => StorageStore());
