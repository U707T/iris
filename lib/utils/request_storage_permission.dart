import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:iris/globals.dart' as globals;
import 'package:iris/utils/logger.dart';
import 'package:permission_handler/permission_handler.dart';

/// 需要申请的存储权限 (Android 11+ 是「所有文件访问权限」)。
Future<Permission> _storagePermission() async {
  try {
    return await isAndroid11OrHigher()
        ? Permission.manageExternalStorage
        : Permission.storage;
  } catch (e) {
    // device_info 不可用时按旧版本处理, 避免整个流程直接抛异常
    logger('Failed to detect Android version: $e');
    return Permission.storage;
  }
}

/// 申请存储权限, 只申请一次。
///
/// 旧实现会在用户拒绝后递归调用自己: Android 10 及以下选择「不再询问」后,
/// `request()` 会立刻返回 denied, 递归便无休止地跑下去 (卡死 / 爆栈)。
/// 现在只申请一次, 结果写回 [globals.storagePermissionStatus],
/// 由调用方根据返回状态决定是否引导用户去系统设置。
Future<PermissionStatus> requestStoragePermission() async {
  if (!Platform.isAndroid) {
    return PermissionStatus.granted;
  }

  final permission = await _storagePermission();

  try {
    var status = await permission.status;
    // 已经永久拒绝时再 request() 不会弹框, 直接交给界面引导去设置
    if (!status.isGranted && !status.isPermanentlyDenied) {
      status = await permission.request();
    }
    globals.storagePermissionStatus = status;
    return status;
  } catch (e) {
    logger('Failed to request storage permission: $e');
    return globals.storagePermissionStatus ?? PermissionStatus.denied;
  }
}

Future<bool> isAndroid11OrHigher() async {
  DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
  AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
  return androidInfo.version.sdkInt >= 30;
}
