import 'dart:io';

import 'package:collection/collection.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_breadcrumb/flutter_breadcrumb.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/models/store/storage_state.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_storage_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/dialogs/show_search_dialog.dart';

/// 文件浏览面板的路径栏：只放面包屑。
///
/// 以前路径出现两次 —— 上面一行面包屑，下面工具条里又写一遍当前文件夹名。
/// 现在路径只在顶部出现一次，底部只留动作。
class FilesBreadcrumb extends StatelessWidget {
  const FilesBreadcrumb({
    super.key,
    required this.storage,
    required this.currentPath,
  });

  final Storage storage;
  final List<String> currentPath;

  @override
  Widget build(BuildContext context) {
    if (currentPath.isEmpty) {
      return Text(storage.name);
    }

    final labels = [
      storage.basePath.length > 1 ? currentPath.first : storage.name,
      ...currentPath.sublist(1),
    ];

    return BreadCrumb.builder(
      itemCount: currentPath.length,
      overflow: Platform.isAndroid || Platform.isIOS
          ? ScrollableOverflow(reverse: true)
          : const WrapOverflow(),
      builder: (index) {
        return BreadCrumbItem(
          content: TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () {
              useStorageStore().updateCurrentPath(
                currentPath.sublist(0, index + 1),
              );
            },
            child: Text(labels[index]),
          ),
        );
      },
      divider: Icon(
        Icons.chevron_right_rounded,
        size: 16,
        color: Theme.of(
          context,
        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
      ),
    );
  }
}

/// 文件浏览面板的底部动作栏：返回 / 主页 / 刷新 / 搜索 / 排序 / 收藏。
///
/// 关闭在标题栏，路径在标题栏 —— 这里只剩动作。
class FilesBottomBar extends HookWidget {
  const FilesBottomBar({
    super.key,
    required this.storage,
    required this.currentPath,
    required this.onBack,
    required this.onRefresh,
  });

  final Storage storage;
  final List<String> currentPath;
  final void Function() onBack;
  final void Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);

    final sortBy = useAppStore().select(context, (state) => state.sortBy);
    final sortOrder = useAppStore().select(context, (state) => state.sortOrder);
    final folderFirst = useAppStore().select(
      context,
      (state) => state.folderFirst,
    );

    final favorites = useStorageStore().select(
      context,
      (state) => state.favorites,
    );
    final currentFavorite = useMemoized(
      () => favorites.firstWhereOrNull(
        (favorite) =>
            favorite.storageId == storage.id && favorite.path == currentPath,
      ),
      [favorites, currentPath],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          IconButton(
            tooltip: t.back,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
            onPressed: onBack,
          ),
          IconButton(
            tooltip: t.home,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.home_rounded, size: 20),
            onPressed: () {
              useStorageStore().updateCurrentStorage(null);
              useStorageStore().updateCurrentPath([]);
            },
          ),
          IconButton(
            tooltip: t.refresh,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: onRefresh,
          ),
          IconButton(
            tooltip: t.search_in_folder,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.search_rounded, size: 20),
            onPressed: () => showSearchDialog(context, storage: storage),
          ),
          PopupMenuButton(
            tooltip: t.sort,
            icon: const Icon(Icons.sort_rounded, size: 20),
            clipBehavior: Clip.hardEdge,
            constraints: const BoxConstraints(minWidth: 200),
            itemBuilder: (context) => [
              PopupMenuItem(
                child: ListTile(
                  mouseCursor: SystemMouseCursors.click,
                  title: Text(t.name),
                  trailing: sortBy == SortBy.name
                      ? Icon(
                          sortOrder == SortOrder.asc
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                        )
                      : null,
                ),
                onTap: () {
                  useAppStore().updateSortBy(SortBy.name);
                  useAppStore().updateSortOrder(
                    sortOrder == SortOrder.desc || sortBy != SortBy.name
                        ? SortOrder.asc
                        : SortOrder.desc,
                  );
                },
              ),
              PopupMenuItem(
                child: ListTile(
                  mouseCursor: SystemMouseCursors.click,
                  title: Text(t.size),
                  trailing: sortBy == SortBy.size
                      ? Icon(
                          sortOrder == SortOrder.asc
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                        )
                      : null,
                ),
                onTap: () {
                  useAppStore().updateSortBy(SortBy.size);
                  useAppStore().updateSortOrder(
                    sortOrder == SortOrder.asc || sortBy != SortBy.size
                        ? SortOrder.desc
                        : SortOrder.asc,
                  );
                },
              ),
              PopupMenuItem(
                child: ListTile(
                  mouseCursor: SystemMouseCursors.click,
                  title: Text(t.last_modified),
                  trailing: sortBy == SortBy.lastModified
                      ? Icon(
                          sortOrder == SortOrder.asc
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                        )
                      : null,
                ),
                onTap: () {
                  useAppStore().updateSortBy(SortBy.lastModified);
                  useAppStore().updateSortOrder(
                    sortOrder == SortOrder.asc || sortBy != SortBy.lastModified
                        ? SortOrder.desc
                        : SortOrder.asc,
                  );
                },
              ),
              PopupMenuItem(
                child: ListTile(
                  mouseCursor: SystemMouseCursors.click,
                  title: Text(t.folder_first),
                  trailing: Checkbox(
                    value: folderFirst,
                    onChanged: (_) {
                      useAppStore().updateFolderFirst(!folderFirst);
                      Navigator.pop(context);
                    },
                  ),
                ),
                onTap: () => useAppStore().updateFolderFirst(!folderFirst),
              ),
            ],
          ),
          IconButton(
            tooltip: currentFavorite != null
                ? t.remove_favorite
                : t.add_favorite,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              currentFavorite != null
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
              size: 20,
            ),
            onPressed: () {
              if (currentFavorite != null) {
                useStorageStore().removeFavorite(currentFavorite);
              } else {
                useStorageStore().addFavorite(
                  Favorite(storageId: storage.id, path: currentPath),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
