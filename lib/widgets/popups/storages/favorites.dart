import 'package:collection/collection.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/storages/local.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/models/store/storage_state.dart';
import 'package:iris/store/use_storage_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/media_row.dart';
import 'package:iris/widgets/panel.dart';
import 'package:path/path.dart' as p;

class Favorites extends HookWidget {
  const Favorites({super.key});

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final favorites = useStorageStore().select(
      context,
      (state) => state.favorites,
    );

    final localStoragesFuture = useMemoized(
      () async => await getLocalStorages(context),
      [],
    );
    final localStorages = useFuture(localStoragesFuture).data ?? [];

    Storage? findStorage(Favorite favorite) {
      final storage = useStorageStore().findById(favorite.storageId);
      if (storage != null) return storage;
      if (favorite.storageId != localStorageId) return null;
      return localStorages.firstWhereOrNull(
        (element) => element.basePath[0] == favorite.path[0],
      );
    }

    String? pathOf(Favorite favorite, Storage storage) {
      if (storage is LocalStorage) {
        return p.normalize(favorite.path.join('/'));
      }
      if (storage is WebDAVStorage) {
        final port =
            storage.port.isNotEmpty &&
                storage.port != '80' &&
                storage.port != '443'
            ? ':${storage.port}'
            : '';
        return 'http${storage.https ? 's' : ''}://${storage.host}$port'
            '${favorite.path.join('/')}';
      }
      return null;
    }

    if (favorites.isEmpty) {
      return PanelEmpty(label: t.no_favorites);
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: favorites.length,
      itemBuilder: (context, index) {
        final favorite = favorites[index];
        final storage = findStorage(favorite);

        return MediaRow(
          icon: Icons.star_rounded,
          title: favorite.path.last,
          meta: storage == null ? null : pathOf(favorite, storage),
          menu: PopupMenuButton<StorageOptions>(
            tooltip: t.menu,
            clipBehavior: Clip.hardEdge,
            onSelected: (value) {
              switch (value) {
                case StorageOptions.remove:
                  useStorageStore().removeFavorite(favorite);
                  break;
                default:
                  break;
              }
            },
            itemBuilder: (BuildContext context) {
              return [
                PopupMenuItem(
                  value: StorageOptions.remove,
                  child: Text(t.remove),
                ),
              ];
            },
          ),
          onTap: storage == null
              ? null
              : () {
                  useStorageStore().updateCurrentPath(favorite.path);
                  useStorageStore().updateCurrentStorage(storage);
                },
        );
      },
    );
  }
}
