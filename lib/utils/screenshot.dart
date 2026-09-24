import 'dart:io';
import 'dart:typed_data';

import 'package:iris/utils/logger.dart';
import 'package:iris/utils/platform.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// 将截图保存到图片目录。
///
/// - Android: 有"所有文件访问"权限时保存到公共图片目录 Pictures/IRIS,
///   否则回退到应用专属外部目录 (无需权限), 避免直接失败。
/// - 桌面: 保存到文档目录下的 Screenshots 文件夹。
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
      final external = await getExternalStorageDirectory();
      final canWritePublicDir =
          external != null && await Permission.manageExternalStorage.isGranted;

      if (canWritePublicDir) {
        // /storage/emulated/0/Android/data/<pkg>/files -> 上级目录中的 Pictures
        final root = external.path.split('/Android/').first;
        dir = Directory(p.join(root, 'Pictures', 'IRIS'));
      } else if (external != null) {
        // 无权限时回退到应用专属外部目录, 保证截图总能保存成功
        dir = Directory(p.join(external.path, 'Screenshots'));
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
