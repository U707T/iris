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

/// 文件浏览面板的底部工具条:
/// 面包屑 + 返回 / 主页 / 刷新 / 搜索 / 排序 / 收藏 / 当前位置 / 关闭。
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
    final folderFirst =
        useAppStore().select(context, (state) => state.folderFirst);

    final favorites =
        useStorageStore().select(context, (state) => state.favorites);
    final currentFavorite = useMemoized(
        () => favorites.firstWhereOrNull((favorite) =>
            favorite.storageId == storage.id && favorite.path == currentPath),
        [favorites, currentPath]);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: BreadCrumb.builder(
            itemCount: currentPath.length,
            overflow: Platform.isAndroid || Platform.isIOS
                ? ScrollableOverflow(reverse: true)
                : const WrapOverflow(),
            builder: (index) {
              return BreadCrumbItem(
                content: TextButton(
                  child: Text([
                    storage.basePath.length > 1
                        ? currentPath.first
                        : storage.name,
                    ...currentPath.sublist(1),
                  ][index]),
                  onPressed: () {
                    useStorageStore()
                        .updateCurrentPath(currentPath.sublist(0, index + 1));
                  },
                ),
              );
            },
            divider: Icon(
              Icons.chevron_right_rounded,
              color:
                  Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(222),
            ),
          ),
        ),
        Divider(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
          height: 0,
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
          child: Row(
            children: [
              IconButton(
                tooltip: t.back,
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: onBack,
              ),
              IconButton(
                tooltip: t.home,
                icon: const Icon(Icons.home_rounded),
                onPressed: () {
                  useStorageStore().updateCurrentStorage(null);
                  useStorageStore().updateCurrentPath([]);
                },
              ),
              IconButton(
                tooltip: t.refresh,
                icon: const Icon(Icons.refresh),
                onPressed: onRefresh,
              ),
              IconButton(
                tooltip: t.search_in_folder,
                icon: const Icon(Icons.search_rounded),
                onPressed: () => showSearchDialog(context, storage: storage),
              ),
              PopupMenuButton(
                tooltip: t.sort,
                icon: const Icon(Icons.sort_rounded),
                clipBehavior: Clip.hardEdge,
                constraints: const BoxConstraints(minWidth: 200),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    child: ListTile(
                      mouseCursor: SystemMouseCursors.click,
                      title: Text(t.name),
                      trailing: sortBy == SortBy.name
                          ? Icon(sortOrder == SortOrder.asc
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded)
                          : null,
                    ),
                    onTap: () {
                      useAppStore().updateSortBy(SortBy.name);
                      useAppStore().updateSortOrder(
                          sortOrder == SortOrder.desc || sortBy != SortBy.name
                              ? SortOrder.asc
                              : SortOrder.desc);
                    },
                  ),
                  PopupMenuItem(
                    child: ListTile(
                      mouseCursor: SystemMouseCursors.click,
                      title: Text(t.size),
                      trailing: sortBy == SortBy.size
                          ? Icon(sortOrder == SortOrder.asc
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded)
                          : null,
                    ),
                    onTap: () {
                      useAppStore().updateSortBy(SortBy.size);
                      useAppStore().updateSortOrder(
                          sortOrder == SortOrder.asc || sortBy != SortBy.size
                              ? SortOrder.desc
                              : SortOrder.asc);
                    },
                  ),
                  PopupMenuItem(
                    child: ListTile(
                      mouseCursor: SystemMouseCursors.click,
                      title: Text(t.last_modified),
                      trailing: sortBy == SortBy.lastModified
                          ? Icon(sortOrder == SortOrder.asc
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded)
                          : null,
                    ),
                    onTap: () {
                      useAppStore().updateSortBy(SortBy.lastModified);
                      useAppStore().updateSortOrder(
                          sortOrder == SortOrder.asc ||
                                  sortBy != SortBy.lastModified
                              ? SortOrder.desc
                              : SortOrder.asc);
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
                          }),
                    ),
                    onTap: () => useAppStore().updateFolderFirst(!folderFirst),
                  ),
                ],
              ),
              IconButton(
                tooltip: currentFavorite != null
                    ? t.remove_favorite
                    : t.add_favorite,
                icon: Icon(currentFavorite != null
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded),
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
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  currentPath.length > 1
                      ? currentPath.last
                      : storage.basePath.length > 1
                          ? currentPath.first
                          : storage.name,
                  maxLines: 1,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: '${t.close} ( Escape )',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
