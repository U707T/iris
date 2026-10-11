import 'package:material_ui/material_ui.dart';

/// Windows 端 Flutter 引擎无障碍桥崩溃的兼容开关（临时，**默认开启 / 已植入 exe**）。
///
/// 背景：Flutter 3.47.x 引擎在 Windows 上存在已知崩溃
/// （flutter/flutter#175041 / #192689）：当 UI 自动化客户端（远程桌面工具、
/// 读屏软件、自动化工具等）在应用启动阶段枚举无障碍树时，
/// `AccessibilityBridge::CreateRemoveReparentedNodesUpdate` 会对空父节点解引用，
/// 进程以 `0xC0000005`（`flutter_windows.dll+0x3c16a`）结束。
/// 引擎无法由应用侧修复；社区验证过的规避方式是给整个应用套一层
/// [ExcludeSemantics]（等价于关闭本应用的 Windows 无障碍支持）。
///
/// 上游修复（PR flutter/flutter#190903 等）仍未发布，因此该规避默认生效，
/// 用户无需任何环境变量 / 命令行参数，双击即用。
///
/// 退出方式（二选一，恢复 Windows 无障碍；请自行承担上述崩溃风险，
/// 例如确实需要屏幕阅读器的用户）：
/// - 环境变量 `IRIS_ENABLE_WINDOWS_A11Y=1`
/// - 命令行参数 `--enable-windows-a11y`
///
/// 旧写法 `IRIS_DISABLE_WINDOWS_A11Y=1` / `--disable-windows-a11y` 依旧接受
/// （默认已开启后是无害的冗余），避免既有快捷方式 / 脚本失效。
/// 待上游引擎修复发布后, 应连同本文件一起移除。
const String kDisableWindowsA11yArgument = '--disable-windows-a11y';
const String kDisableWindowsA11yEnvironment = 'IRIS_DISABLE_WINDOWS_A11Y';
const String kEnableWindowsA11yArgument = '--enable-windows-a11y';
const String kEnableWindowsA11yEnvironment = 'IRIS_ENABLE_WINDOWS_A11Y';

bool _isTruthyFlag(String? value) {
  if (value == null) return false;
  switch (value.trim().toLowerCase()) {
    case '1':
    case 'true':
    case 'yes':
    case 'on':
      return true;
  }
  return false;
}

/// 是否关闭 Windows 无障碍集成（见文件顶部说明）。
///
/// - 非 Windows：始终 false；
/// - Windows：默认 true（兼容默认植入）；显式设置 `IRIS_ENABLE_WINDOWS_A11Y=1`
///   或传入 `--enable-windows-a11y` 时返回 false（恢复无障碍）。
///
/// 参数可注入, 便于测试。
bool shouldDisableWindowsA11y({
  required bool isWindows,
  required Map<String, String> environment,
  required List<String> arguments,
}) {
  if (!isWindows) return false;
  if (_isTruthyFlag(environment[kEnableWindowsA11yEnvironment]) ||
      arguments.contains(kEnableWindowsA11yArgument)) {
    return false;
  }
  return true;
}

/// 按需把 [child] 包进 [ExcludeSemantics]（见文件顶部说明）。
Widget maybeExcludeSemantics({
  required Widget child,
  required bool disabled,
}) {
  return disabled ? ExcludeSemantics(child: child) : child;
}
