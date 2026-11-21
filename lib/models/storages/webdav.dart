import 'dart:convert';

import 'package:iris/models/storages/directory_scan.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/utils/check_content_type.dart';
import 'package:iris/utils/logger.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;
import 'package:iris/models/file.dart';

/// 把存储里的 path 拆成真正的 URI 段。
///
/// WebDAV 的 basePath 允许是 `/dav/movies` 这种带斜杠的单段 (对话框直接输入),
/// 而 `Uri(pathSegments: ...)` 需要的是 `['dav', 'movies']`。直接去掉斜杠会
/// 变成 `davmovies`, 导致媒体 URL 少一层目录。
List<String> webDAVPathSegments(List<String> path) => [
  for (final part in path)
    for (final segment in part.split('/'))
      if (segment.isNotEmpty) segment,
];

/// 生成 WebDAV 上某个文件的完整 URL。
///
/// 文件名必须作为 pathSegments 传入, 不能走 `Uri.resolve(fileName)`:
/// 文件名里的 `#` / `?` 会被当成 fragment / query 分隔符, 空格等字符也会
/// 按 URI 引用规则处理, 最终取到错误的资源。
String buildWebDAVFileUri({
  required WebDAVStorage storage,
  required List<String> path,
  required String fileName,
}) {
  final segments = webDAVPathSegments(path);
  return Uri(
    scheme: storage.https ? 'https' : 'http',
    host: storage.host,
    port: int.tryParse(storage.port),
    pathSegments: [...segments, fileName],
  ).toString();
}

Future<bool> testWebDAV(WebDAVStorage storage) async {
  final host = storage.host;
  final port = storage.port;
  final username = storage.username;
  final password = storage.password;
  final https = storage.https;
  final basePath = storage.basePath;

  try {
    var client = webdav.newClient(
      "http${https ? 's' : ''}://$host:$port",
      user: username,
      password: password,
      debug: false,
    );

    client.setHeaders({'accept-charset': 'utf-8'});
    client.setConnectTimeout(4000);
    client.setSendTimeout(4000);
    client.setReceiveTimeout(4000);

    // await client.ping();
    await client.readDir(basePath.join('/'));
    return true;
  } catch (e) {
    logger(e.toString());
    return false;
  }
}

Future<List<FileItem>> getWebDAVFiles(
  WebDAVStorage storage,
  List<String> path, {
  bool mediaOnly = false,
  DirectoryScan? scan,
}) async {
  if (scan?.isCancelled == true) return [];
  final client = webdav.newClient(
    "http${storage.https ? 's' : ''}://${storage.host}:${storage.port}",
    user: storage.username,
    password: storage.password,
    debug: false,
  );

  client.setHeaders({'accept-charset': 'utf-8'});
  client.setConnectTimeout(8000);
  client.setSendTimeout(8000);
  client.setReceiveTimeout(8000);

  // Each listing owns its client, so closing it only aborts this request.
  var closed = false;
  void closeClient() {
    if (closed) return;
    closed = true;
    client.c.close(force: true);
  }

  final unregister = scan?.onCancel(closeClient);
  try {
    final files = await client.readDir(path.join('/'));
    if (scan?.isCancelled == true) return [];

    final fileItems = <FileItem>[];
    for (final file in files) {
      final fileName = file.name;
      if (fileName == null) continue;

      final isDir = file.isDir ?? false;
      final type = isDir ? ContentType.other : checkContentType(fileName);
      if (mediaOnly &&
          !isDir &&
          type != ContentType.video &&
          type != ContentType.audio) {
        continue;
      }
      fileItems.add(
        FileItem(
          storageId: storage.id,
          storageType: StorageType.webdav,
          name: fileName,
          uri: buildWebDAVFileUri(
            storage: storage,
            path: path,
            fileName: fileName,
          ),
          path: [...path, fileName],
          isDir: isDir,
          size: file.size ?? 0,
          lastModified: file.mTime,
          type: type,
        ),
      );
    }
    return fileItems;
  } catch (_) {
    if (scan?.isCancelled == true) return [];
    rethrow;
  } finally {
    unregister?.call();
    closeClient();
  }
}

/// Return credentials only for this connection's exact HTTP origin.
/// A persisted media URL may predate an edit to the connection configuration.
String getWebDAVAuthForUri(WebDAVStorage storage, String mediaUri) {
  final target = Uri.tryParse(mediaUri);
  final origin = Uri(
    scheme: storage.https ? 'https' : 'http',
    host: storage.host,
    port: storage.port.isEmpty ? null : int.tryParse(storage.port),
  );
  final configuredPort = int.tryParse(storage.port);
  if ((storage.port.isNotEmpty &&
          (configuredPort == null ||
              configuredPort < 1 ||
              configuredPort > 65535)) ||
      target == null ||
      !target.hasAuthority ||
      target.userInfo.isNotEmpty ||
      target.scheme != origin.scheme ||
      target.host.toLowerCase() != origin.host.toLowerCase() ||
      target.port != origin.port ||
      target.host.isEmpty) {
    throw StateError(
      'The media URL no longer belongs to this WebDAV connection',
    );
  }
  return getWebDAVAuth(storage);
}

String getWebDAVAuth(WebDAVStorage storage) =>
    'Basic ${base64Encode(utf8.encode('${storage.username}:${storage.password}'))}';
