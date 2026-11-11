import 'dart:io';

/// 桌面宿主的判定结果 (进程内固定)。
final bool _isDesktop =
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// 测试专用: 在桌面宿主上模拟移动端布局 (或反过来)。
///
/// 命名跟 Flutter 自己的 `debugDefaultTargetPlatformOverride` 一致 ——
/// 单元测试跑在 Linux 上, 但被测的是手机布局 (控制栏第二排的「横竖屏」
/// 按钮只在移动端出现), 没有这个开关就只能靠肉眼验。
/// **生产代码一律不要写它**: 平台判定本身是常量, 写一次就把整个 App 的
/// 布局改错, 而且不会有任何报错。
bool? debugIsDesktopOverride;

bool get isDesktop => debugIsDesktopOverride ?? _isDesktop;

final bool isWindows = Platform.isWindows;
final bool isLinux = Platform.isLinux;
final bool isMacOS = Platform.isMacOS;
final bool isAndroid = Platform.isAndroid;
final bool isIOS = Platform.isIOS;
