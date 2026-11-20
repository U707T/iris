import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/hooks/use_material_tab_controller.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/store/use_storage_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/path_conv.dart';
import 'package:iris/utils/platform.dart';
import 'package:iris/widgets/dialogs/show_folder_dialog.dart';
import 'package:iris/widgets/dialogs/show_webdav_dialog.dart';
import 'package:iris/widgets/panel.dart';
import 'package:iris/widgets/popups/storages/favorites.dart';
import 'package:iris/widgets/popups/storages/files.dart';
import 'package:iris/widgets/popups/storages/storages_list.dart';
import 'package:saf_util/saf_util.dart';

class Storages extends HookWidget {
  const Storages({super.key});

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final currentStorage = useStorageStore().select(
      context,
      (state) => state.currentStorage,
    );

    final tabs = <(String, Widget)>[
      (t.storage, const StoragesList()),
      (t.favorites, const Favorites()),
    ];

    final tabController = useMaterialTabController(initialLength: tabs.length);

    return currentStorage != null
        ? Files(storage: currentStorage)
        : Column(
            children: [
              PanelHeader(
                title: TabBar(
                  controller: tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  dividerColor: Colors.transparent,
                  tabs: [for (final (label, _) in tabs) Tab(text: label)],
                ),
                actions: [
                  PopupMenuButton<StorageType>(
                    tooltip: t.add_storage,
                    icon: const Icon(Icons.add_rounded, size: 20),
                    iconColor: Theme.of(context).colorScheme.onSurfaceVariant,
                    clipBehavior: Clip.hardEdge,
                    onSelected: (StorageType value) {
                      switch (value) {
                        case StorageType.internal:
                        case StorageType.network:
                        case StorageType.usb:
                        case StorageType.sdcard:
                          () async {
                            if (isAndroid) {
                              final dir = await SafUtil().pickDirectory(
                                persistablePermission: true,
                              );
                              if (dir != null && context.mounted) {
                                showFolderDialog(
                                  context,
                                  storage: LocalStorage(
                                    type: value,
                                    name: dir.name,
                                    basePath: [dir.uri],
                                  ),
                                );
                              }
                            } else {
                              String? selectedDirectory =
                                  await FilePicker.getDirectoryPath();

                              if (selectedDirectory != null &&
                                  context.mounted) {
                                showFolderDialog(
                                  context,
                                  storage: LocalStorage(
                                    type: value,
                                    name: pathConv(selectedDirectory).last,
                                    basePath: pathConv(selectedDirectory),
                                  ),
                                );
                              }
                            }
                          }();
                          break;
                        case StorageType.webdav:
                          showWebDAVDialog(context);
                          break;
                        case StorageType.none:
                          break;
                      }
                    },
                    itemBuilder: (BuildContext context) {
                      return [
                        PopupMenuItem<StorageType>(
                          value: StorageType.internal,
                          child: Text(t.folder),
                        ),
                        const PopupMenuItem<StorageType>(
                          value: StorageType.webdav,
                          child: Text('WebDAV'),
                        ),
                      ];
                    },
                  ),
                ],
              ),
              const PanelDivider(),
              Expanded(
                child: TabBarView(
                  controller: tabController,
                  children: [for (final (_, child) in tabs) child],
                ),
              ),
            ],
          );
  }
}
