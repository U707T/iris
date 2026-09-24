import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/utils/platform.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 将截图保存到应用图片目录 (Android 为 Pictures/IRIS, 桌面为应用文档目录)。
///
/// 返回保存后的文件路径, 失败返回 null。
Future<String?> saveScreenshot({
  required Uint8List bytes,
  required String fileNamePrefix,
  required String extension,
}) async {
  try {
    final Directory dir;

    if (isAndroid) {
      // Android: 保存到外部存储的 Pictures/IRIS 目录
      final external = await getExternalStorageDirectory();
      if (external != null) {
        // /storage/emulated/0/Android/data/<pkg>/files -> 上级目录中的 Pictures
        final root = external.path.split('/Android/').first;
        dir = Directory(p.join(root, 'Pictures', 'IRIS'));
      } else {
        dir = await getApplicationDocumentsDirectory();
      }
    } else {
      final documents = await getApplicationDocumentsDirectory();
      dir = Directory(p.join(documents.path, 'Screenshots'));
    }

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final name = '${fileNamePrefix}_$timestamp.$extension';
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(bytes, flush: true);

    logger('Screenshot saved: ${file.path}');
    return file.path;
  } catch (e) {
    logger('Error saving screenshot: $e');
    return null;
  }
}

/// 显示截图结果提示
void showScreenshotToast(BuildContext context, String? path) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  messenger.showSnackBar(
    SnackBar(
      content: Text(path != null ? '已保存: $path' : '截图失败'),
      duration: const Duration(seconds: 3),
    ),
  );
}
