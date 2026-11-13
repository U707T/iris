// ignore: unnecessary_library_name
library my_app.globals;

import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';

List<String> arguments = [];
String? initUri;
PermissionStatus? storagePermissionStatus;

/// 本次启动由命令行 / Intent 显式打开文件 (应自动播放)。
///
/// 不直接 `updateAutoPlay(true)`: AppStore 与 PlayQueueStore 是两个独立
/// 异步 load 的 store, 谁后完成谁说了算; 直接写会被 AppState.load 里的
/// `autoPlay: false` 覆盖 (表现为"双击文件打开了却不播")。AppState.load
/// 会读这个标记, 两种加载顺序都能得到正确结果。
bool autoPlayOnLaunch = false;

/// Windows 无障碍兼容开关 (规避引擎崩溃 flutter/flutter#175041)。
/// 见 lib/utils/windows_a11y_compat.dart; main() 启动时按环境变量 / 命令行参数设置。
bool disableWindowsA11y = false;

/// 画中画能力 (main() 启动时探测一次)。
///
/// Android 要 API >= 26 且系统声明 FEATURE_PICTURE_IN_PICTURE; 桌面端走
/// 应用内小窗, 恒为 true; iOS 没有实现, 恒为 false。设置页的开关和「更多」
/// 菜单的入口都读这一份结果, 免得每次 build 都去问一次原生。
bool pictureInPictureSupported = false;

/// 主窗口的最小尺寸。普通模式下它是控制栏 / 标题栏不被挤坏的下限;
/// 画中画小窗会临时放宽到更小, 退出时再恢复成这个值 (见 picture_in_picture.dart)。
const Size minimumWindowSize = Size(427, 240);
final moreMenuKey = GlobalKey<PopupMenuButtonState>();
final rateMenuKey = GlobalKey<PopupMenuButtonState>();
const double minZoom = 0.25;
const double maxZoom = 5.0;
const double zoomStep = 0.05;

/// 100% 附近的吸附死区: 手动缩放落进 ±3% 就贴回原始大小。
///
/// 必须小于 [zoomStep] (5%) —— 否则缩放面板的「+ / -」从 100% 出发一步就
/// 落回死区里, 按钮看起来像坏了。用户也不必再用双指 / 滚轮去"抠" 100%:
/// 松手前只要接近原大小, 手感和双击复位一样干净。
const double zoomSnapThreshold = 0.03;
const List<double> longPressSpeedStops = [
  1.25,
  1.5,
  1.75,
  2.0,
  2.5,
  3.0,
  4.0,
  5.0,
];
const List<double> speedStops = [
  0.25,
  0.5,
  0.75,
  1.0,
  1.25,
  1.5,
  1.75,
  2.0,
  3.0,
  4.0,
  5.0,
  6.0,
  7.0,
  8.0,
  9.0,
  10.0,
];
