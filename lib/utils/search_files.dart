import 'package:iris/models/file.dart';
import 'package:iris/models/storages/storage.dart';

/// Recursively searches video and audio files whose name contains [query]
/// (case-insensitive) under [basePath].
///
/// The search is breadth-first and limited by [maxDepth] and [maxResults]
/// to keep it responsive on large folder trees and slow network storages.
///
/// [isCancelled] 在每个目录开始前检查一次; 对话框关闭 / 发起新搜索时传进来,
/// 让后台不再继续扫网络目录 (只丢弃结果的话, 旧搜索仍会跑完整棵树)。
Future<List<FileItem>> searchFiles({
  required Storage storage,
  required List<String> basePath,
  required String query,
  int maxDepth = 5,
  int maxResults = 200,
  bool Function()? isCancelled,
}) async {
  final trimmed = query.trim().toLowerCase();
  if (trimmed.isEmpty) return [];

  final results = <FileItem>[];
  final queue = <(List<String>, int)>[(basePath, 0)];

  bool cancelled() => isCancelled?.call() ?? false;

  while (queue.isNotEmpty && results.length < maxResults) {
    if (cancelled()) break;
    final (path, depth) = queue.removeAt(0);

    List<FileItem> files;
    try {
      files = await storage.getFiles(path);
    } catch (_) {
      continue;
    }
    if (cancelled()) break;

    for (final file in files) {
      if (file.isDir == true && file.name.isNotEmpty) {
        if (depth < maxDepth) {
          queue.add(([...path, file.name], depth + 1));
        }
        continue;
      }

      if ([ContentType.video, ContentType.audio].contains(file.type) &&
          file.name.toLowerCase().contains(trimmed)) {
        results.add(file);
        if (results.length >= maxResults) break;
      }
    }
  }

  return results;
}
