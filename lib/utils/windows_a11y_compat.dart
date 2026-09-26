import 'package:material_ui/material_ui.dart';

/// Windows 端 Flutter 引擎无障碍桥崩溃的兼容开关（临时，默认关闭）。
///
/// 背景：Flutter 3.47.x 引擎在 Windows 上存在已知崩溃
/// （flutter/flutter#175041 / #192689）：当 UI 自动化客户端（远程桌面工具、
/// 读屏软件、自动化工具等）在应用启动阶段枚举无障碍树时，
/// `AccessibilityBridge::CreateRemoveReparentedNodesUpdate` 会对空父节点解引用，
/// 进程以 `0xC0000005`（`flutter_windows.dll+0x3c16a`）结束。
/// 引擎无法由应用侧修复；社区验证过的规避方式是给整个应用套一层
/// [ExcludeSemantics]（等价于关闭本应用的 Windows 无障碍支持）。
///
/// 开启方式（二选一，默认关闭，仅 Windows 生效）：
/// - 环境变量 `IRIS_DISABLE_WINDOWS_A11Y=1`
/// - 命令行参数 `--disable-windows-a11y`
///
/// 待上游引擎修复（PR flutter/flutter#190903 等）发布后, 应移除本开关。
const String kDisableWindowsA11yArgument = '--disable-windows-a11y';
const String kDisableWindowsA11yEnvironment = 'IRIS_DISABLE_WINDOWS_A11Y';

/// 是否要求关闭 Windows 无障碍集成（见文件顶部说明）。
///
/// 参数可注入, 便于测试。
bool shouldDisableWindowsA11y({
  required bool isWindows,
  required Map<String, String> environment,
  required List<String> arguments,
}) {
  if (!isWindows) return false;
  final value = environment[kDisableWindowsA11yEnvironment];
  if (value != null) {
    switch (value.trim().toLowerCase()) {
      case '1':
      case 'true':
      case 'yes':
      case 'on':
        return true;
    }
  }
  return arguments.contains(kDisableWindowsA11yArgument);
}

/// 按需把 [child] 包进 [ExcludeSemantics]（见文件顶部说明）。
Widget maybeExcludeSemantics({
  required Widget child,
  required bool disabled,
}) {
  return disabled ? ExcludeSemantics(child: child) : child;
}
