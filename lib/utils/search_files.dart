import 'package:iris/models/file.dart';
import 'package:iris/models/storages/storage.dart';

/// Recursively searches video and audio files whose name contains [query]
/// (case-insensitive) under [basePath].
///
/// The search is breadth-first and limited by [maxDepth] and [maxResults]
/// to keep it responsive on large folder trees and slow network storages.
Future<List<FileItem>> searchFiles({
  required Storage storage,
  required List<String> basePath,
  required String query,
  int maxDepth = 5,
  int maxResults = 200,
}) async {
  final trimmed = query.trim().toLowerCase();
  if (trimmed.isEmpty) return [];

  final results = <FileItem>[];
  final queue = <(List<String>, int)>[(basePath, 0)];

  while (queue.isNotEmpty && results.length < maxResults) {
    final (path, depth) = queue.removeAt(0);

    List<FileItem> files;
    try {
      files = await storage.getFiles(path);
    } catch (_) {
      continue;
    }

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
