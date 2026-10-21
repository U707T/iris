import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/globals.dart' show moreMenuKey;
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/models/storages/local.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:iris/utils/exit_app.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/platform.dart';
import 'package:iris/utils/take_screenshot.dart';
import 'package:iris/widgets/bottom_sheets/show_open_link_bottom_sheet.dart';
import 'package:iris/widgets/dialogs/show_open_link_dialog.dart';
import 'package:iris/widgets/dialogs/show_rate_dialog.dart';
import 'package:iris/widgets/dialogs/show_rotate_dialog.dart';
import 'package:iris/widgets/dialogs/show_shortcuts_dialog.dart';
import 'package:iris/widgets/popup.dart';
import 'package:iris/widgets/popups/history.dart';
import 'package:iris/widgets/popups/settings/settings.dart';
import 'package:iris/widgets/popups/storages/storages.dart';
import 'package:iris/widgets/popups/track/track_panel.dart';
import 'package:provider/provider.dart';

/// 控制栏右侧的「更多」菜单 (打开文件 / 链接、截图、旋转、短视频、
/// 统计、快捷键、历史、设置、退出)
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
      itemBuilder: (BuildContext context) => [
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
      ],
    );
  }
}
