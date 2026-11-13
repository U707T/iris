import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/globals.dart' show moreMenuKey;
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/models/storages/local.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:iris/utils/exit_app.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/picture_in_picture.dart';
import 'package:iris/utils/platform.dart';
import 'package:iris/utils/take_screenshot.dart';
import 'package:iris/widgets/bottom_sheets/show_open_link_bottom_sheet.dart';
import 'package:iris/widgets/dialogs/show_open_link_dialog.dart';
import 'package:iris/widgets/dialogs/show_orientation_dialog.dart';
import 'package:iris/widgets/dialogs/show_rate_dialog.dart';
import 'package:iris/widgets/dialogs/show_rotate_dialog.dart';
import 'package:iris/widgets/dialogs/show_shortcuts_dialog.dart';
import 'package:iris/widgets/dialogs/show_zoom_dialog.dart';
import 'package:iris/widgets/popup.dart';
import 'package:iris/widgets/popups/history.dart';
import 'package:iris/widgets/popups/settings/settings.dart';
import 'package:iris/widgets/popups/storages/storages.dart';
import 'package:iris/widgets/popups/track/track_panel.dart';
import 'package:provider/provider.dart';

/// 控制栏右侧的「更多」菜单 (打开文件 / 链接、截图、旋转、缩放、
/// 屏幕方向、短视频、统计、快捷键、历史、设置、退出)
class MoreMenuButton extends HookWidget {
  const MoreMenuButton({
    super.key,
    required this.file,
    required this.width,
    required this.hasVideos,
    this.compact = false,
    required this.showControl,
    required this.showControlForHover,
    required this.onEnterShortVideo,
    this.color,
    this.overlayColor,
  });

  final FileItem? file;
  final double width;
  final bool hasVideos;

  /// 控制栏放不下时, 音轨 / 存储 / 全屏入口收进这里
  final bool compact;
  final void Function() showControl;
  final Future<void> Function(Future<void> callback) showControlForHover;
  final VoidCallback onEnterShortVideo;
  final Color? color;
  final WidgetStateProperty<Color?>? overlayColor;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final rate = useAppStore().select(context, (state) => state.rate);
    final isFullScreen =
        usePlayerUiStore().select(context, (state) => state.isFullScreen);
    // 「缩放」原来在控制栏上占一个放大镜按钮; 按钮让位给刷新 / 横竖屏后,
    // 精确调节 (滑条 + 步进) 收到这里, 手势之外仍然有入口。
    final zoom = usePlayerUiStore().select(context, (state) => state.zoom);
    // 画中画开关与当前画面的宽高比: 进入小窗时按它定形状 (Android 的
    // PictureInPictureParams, 桌面小窗的尺寸都读这一份)。
    final bool pictureInPicture =
        useAppStore().select(context, (state) => state.pictureInPicture);
    final double aspectRatio =
        usePlayerUiStore().select(context, (state) => state.aspectRatio);
    // 「屏幕方向」与设置里那一项读写同一份状态, 这里只是把入口从四层提到两层
    final ScreenOrientation screenOrientation =
        useAppStore().select(context, (state) => state.orientation);
    final orientationLabels = {
      ScreenOrientation.device: t.device,
      ScreenOrientation.landscape: t.landscape,
      ScreenOrientation.portrait: t.portrait,
    };

    return PopupMenuButton(
      key: moreMenuKey,
      icon: Icon(
        Icons.more_vert_rounded,
        size: 20,
        color: color,
      ),
      style: ButtonStyle(overlayColor: overlayColor),
      clipBehavior: Clip.hardEdge,
      constraints: const BoxConstraints(minWidth: 200),
      itemBuilder: (BuildContext context) {
        // 按使用场景分四组: 打开内容 → 画面与方向 → 播放与队列 → 应用。
        // 每一项自己的显示条件 (窄屏 / 视频 / 桌面 ...) 保持在原处;
        // 空组不出现, 分隔线只在两组都有内容时才插。
        // 打开内容
        final List<PopupMenuEntry<dynamic>> openGroup = [
          PopupMenuItem(
            child: ListTile(
              mouseCursor: SystemMouseCursors.click,
              leading: const Icon(
                Icons.file_open_rounded,
                size: 16.5,
              ),
              title: Text(t.open_file),
              trailing: Text(
                'Ctrl + O',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).dividerColor,
                ),
              ),
            ),
            onTap: () async {
              showControl();
              if (Platform.isAndroid) {
                await pickContentFile();
              } else {
                await pickLocalFile();
              }
              showControl();
            },
          ),
          PopupMenuItem(
            child: ListTile(
              mouseCursor: SystemMouseCursors.click,
              leading: const Icon(
                Icons.file_present_rounded,
                size: 16.5,
              ),
              title: Text(t.open_link),
              trailing: Text(
                'Ctrl + L',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).dividerColor,
                ),
              ),
            ),
            onTap: () async {
              isDesktop
                  ? await showOpenLinkDialog(context)
                  : await showOpenLinkBottomSheet(context);
              showControl();
            },
          ),
          if (compact)
            PopupMenuItem(
              child: ListTile(
                mouseCursor: SystemMouseCursors.click,
                leading: const Icon(Icons.storage_rounded, size: 20),
                title: Text(t.storage),
              ),
              onTap: () => showControlForHover(
                showPopup(
                  context: context,
                  child: const Storages(),
                  direction: PopupDirection.right,
                ),
              ),
            ),
        ];
        // 画面与方向
        final List<PopupMenuEntry<dynamic>> viewGroup = [
          // 截图
          if (file?.type == ContentType.video)
            PopupMenuItem(
              child: ListTile(
                mouseCursor: SystemMouseCursors.click,
                leading: const Icon(Icons.photo_camera_rounded, size: 20),
                title: Text(t.screenshot),
                trailing: Text(
                  'Ctrl + S',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).dividerColor,
                  ),
                ),
              ),
              onTap: () async {
                showControl();
                await takeScreenshot(context, context.read<MediaPlayer>());
                showControl();
              },
            ),
          // 画面旋转
          if (file?.type == ContentType.video)
            PopupMenuItem(
              child: ListTile(
                mouseCursor: SystemMouseCursors.click,
                leading: const Icon(Icons.screen_rotation_alt_rounded, size: 20),
                title: Text(t.rotate),
                trailing: Text(
                  'Ctrl + T',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).dividerColor,
                  ),
                ),
              ),
              onTap: () => showControlForHover(showRotateDialog(context)),
            ),
          // 画面缩放: 100% 附近会吸附回原始大小 (见 PlayerUiStore.updateZoom)
          if (file?.type != ContentType.audio)
            PopupMenuItem(
              child: ListTile(
                mouseCursor: SystemMouseCursors.click,
                leading: const Icon(Icons.zoom_in_rounded, size: 20),
                title: Text(t.zoom),
                trailing: Text(
                  '${(zoom * 100).round()}%',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).dividerColor,
                  ),
                ),
              ),
              onTap: () => showControlForHover(showZoomDialog(context)),
            ),
          // 画中画: 设置里的总开关关着就不出现 —— 开关本身就是"要不要这个能力",
          // 留着入口反而会让人以为设置没生效。
          if (file?.type == ContentType.video &&
              PictureInPicture.isSupported &&
              pictureInPicture)
            PopupMenuItem(
              child: ListTile(
                mouseCursor: SystemMouseCursors.click,
                leading:
                    const Icon(Icons.picture_in_picture_alt_rounded, size: 20),
                title: Text(t.enter_picture_in_picture),
              ),
              onTap: () {
                showControl();
                unawaited(PictureInPicture.enter(aspectRatio: aspectRatio));
              },
            ),
          // 屏幕方向: 设置里那一项埋在「更多 → 设置 → 播放 → 屏幕方向」四层之下,
          // 这里给同一份设置一个两层入口 (设备 / 横向 / 纵向, 与原对话框一致)。
          // 系统小窗 / 分屏要按横屏铺开时, 不用再翻进设置。
          if (!isDesktop)
            PopupMenuItem(
              child: ListTile(
                mouseCursor: SystemMouseCursors.click,
                leading: const Icon(Icons.screen_rotation_rounded, size: 20),
                title: Text(t.screen_orientation),
                trailing: Text(
                  orientationLabels[screenOrientation] ??
                      screenOrientation.name,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).dividerColor,
                  ),
                ),
              ),
              onTap: () => showControlForHover(showOrientationDialog(context)),
            ),
          if (compact && isDesktop)
            PopupMenuItem(
              child: ListTile(
                mouseCursor: SystemMouseCursors.click,
                leading: Icon(
                  isFullScreen
                      ? Icons.close_fullscreen_rounded
                      : Icons.open_in_full_rounded,
                  size: 20,
                ),
                title: Text(
                  isFullScreen ? t.exit_fullscreen : t.enter_fullscreen,
                ),
              ),
              onTap: () =>
                  usePlayerUiStore().updateFullScreen(!isFullScreen),
            ),
        ];
        // 播放与队列
        final List<PopupMenuEntry<dynamic>> playbackGroup = [
          if (width < 600)
            PopupMenuItem(
              child: ListTile(
                mouseCursor: SystemMouseCursors.click,
                leading: const Icon(
                  Icons.speed_rounded,
                  size: 20,
                ),
                title: Text('${t.playback_speed}: ${rate}X'),
              ),
              onTap: () => showControlForHover(showRateDialog(context)),
            ),
          if (compact)
            PopupMenuItem(
              child: ListTile(
                mouseCursor: SystemMouseCursors.click,
                leading: const Icon(Icons.graphic_eq_rounded, size: 20),
                title: Text(t.audio_track),
              ),
              onTap: () => showControlForHover(
                showPopup(
                  context: context,
                  child: Provider<MediaPlayer>.value(
                    value: context.read<MediaPlayer>(),
                    child: const TrackPanel(),
                  ),
                  direction: PopupDirection.right,
                ),
              ),
            ),
          // 短视频模式
          if (hasVideos)
            PopupMenuItem(
              onTap: onEnterShortVideo,
              child: ListTile(
                mouseCursor: SystemMouseCursors.click,
                leading: const Icon(Icons.swipe_vertical_rounded, size: 20),
                title: Text(t.short_video_mode),
              ),
            ),
          // 播放统计
          PopupMenuItem(
            child: ListTile(
              mouseCursor: SystemMouseCursors.click,
              leading: const Icon(Icons.monitor_heart_rounded, size: 20),
              title: Text(t.playback_stats),
              trailing: Text(
                'Ctrl + I',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).dividerColor,
                ),
              ),
            ),
            onTap: () {
              usePlayerUiStore().toggleIsShowStats();
              showControl();
            },
          ),
        ];
        // 应用
        final List<PopupMenuEntry<dynamic>> appGroup = [
          // 快捷键
          if (isDesktop)
            PopupMenuItem(
              child: ListTile(
                mouseCursor: SystemMouseCursors.click,
                leading: const Icon(Icons.keyboard_rounded, size: 20),
                title: Text(t.shortcuts),
              ),
              onTap: () => showControlForHover(showShortcutsDialog(context)),
            ),
          PopupMenuItem(
            child: ListTile(
              mouseCursor: SystemMouseCursors.click,
              leading: const Icon(
                Icons.history_rounded,
                size: 20,
              ),
              title: Text(t.history),
              trailing: Text(
                'Ctrl + H',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).dividerColor,
                ),
              ),
            ),
            onTap: () => showControlForHover(
              showPopup(
                context: context,
                child: const History(),
                direction: PopupDirection.right,
              ),
            ),
          ),
          PopupMenuItem(
            child: ListTile(
              mouseCursor: SystemMouseCursors.click,
              leading: const Icon(
                Icons.settings_rounded,
                size: 20,
              ),
              title: Text(t.settings),
              trailing: Text(
                'Ctrl + P',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).dividerColor,
                ),
              ),
            ),
            onTap: () => showControlForHover(
              showPopup(
                context: context,
                child: const Settings(),
                direction: PopupDirection.right,
              ),
            ),
          ),
          PopupMenuItem(
            child: ListTile(
              mouseCursor: SystemMouseCursors.click,
              leading: const Icon(
                Icons.exit_to_app_rounded,
                size: 20,
              ),
              title: Text(t.exit),
              trailing: Text(
                'Alt + X',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).dividerColor,
                ),
              ),
            ),
            onTap: () async {
              await exitApp(context.read<MediaPlayer>());
            },
          ),
        ];

        final groups = <List<PopupMenuEntry<dynamic>>>[
          openGroup,
          viewGroup,
          playbackGroup,
          appGroup,
        ];

        final entries = <PopupMenuEntry<dynamic>>[];
        for (final group in groups) {
          if (group.isEmpty) continue;
          if (entries.isNotEmpty) entries.add(const PopupMenuDivider());
          entries.addAll(group);
        }
        return entries;
      },
    );
  }
}
