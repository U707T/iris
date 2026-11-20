import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/storages/local.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/store/use_storage_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/dialogs/show_folder_dialog.dart';
import 'package:iris/widgets/dialogs/show_webdav_dialog.dart';
import 'package:iris/widgets/media_row.dart';
import 'package:iris/widgets/panel.dart';
import 'package:path/path.dart' as p;

class StoragesList extends HookWidget {
  const StoragesList({super.key});

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);

    final localStoragesFuture = useMemoized(
      () async => await getLocalStorages(context),
      [],
    );
    final localStorages = useFuture(localStoragesFuture).data ?? [];

    final storages = useStorageStore().select(
      context,
      (state) => state.storages,
    );

    final allStorages = useMemoized(() => [...localStorages, ...storages], [
      localStorages,
      storages,
    ]);

    if (allStorages.isEmpty) {
      return PanelEmpty(label: t.no_storages);
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: allStorages.length,
      itemBuilder: (context, index) {
        final storage = allStorages[index];

        final String? path = switch (storage.type) {
          StorageType.internal ||
          StorageType.network ||
          StorageType.usb ||
          StorageType.sdcard => p.normalize(storage.basePath.join('/')),
          StorageType.webdav => () {
            final webdav = storage as WebDAVStorage;
            final port =
                webdav.port.isNotEmpty &&
                    webdav.port != '80' &&
                    webdav.port != '443'
                ? ':${webdav.port}'
                : '';
            return 'http${webdav.https ? 's' : ''}://${webdav.host}$port'
                '${webdav.basePath.join('/')}';
          }(),
          StorageType.none => null,
        };

        return MediaRow(
          icon: storage.type == StorageType.webdav
              ? Icons.cloud_rounded
              : Icons.folder_rounded,
          title: storage.name,
          meta: path,
          menu: localStorages.contains(storage)
              ? null
              : PopupMenuButton<StorageOptions>(
                  tooltip: t.menu,
                  clipBehavior: Clip.hardEdge,
                  onSelected: (value) {
                    switch (value) {
                      case StorageOptions.edit:
                        switch (storage.type) {
                          case StorageType.internal:
                          case StorageType.network:
                          case StorageType.usb:
                          case StorageType.sdcard:
                            showFolderDialog(
                              context,
                              storage: storage as LocalStorage,
                            );
                            break;
                          case StorageType.webdav:
                            showWebDAVDialog(
                              context,
                              storage: storage as WebDAVStorage,
                            );
                            break;
                          case StorageType.none:
                            break;
                        }
                        break;
                      case StorageOptions.remove:
                        useStorageStore().removeStorage(storage);
                        break;
                    }
                  },
                  itemBuilder: (BuildContext context) {
                    return [
                      PopupMenuItem(
                        value: StorageOptions.edit,
                        child: Text(t.edit),
                      ),
                      PopupMenuItem(
                        value: StorageOptions.remove,
                        child: Text(t.remove),
                      ),
                    ];
                  },
                ),
          onTap: () {
            useStorageStore().updateCurrentPath(storage.basePath);
            useStorageStore().updateCurrentStorage(storage);
          },
        );
      },
    );
  }
}
