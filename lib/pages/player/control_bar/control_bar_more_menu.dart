import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/globals.dart' show openMoreMenu;
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/models/storages/local.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:iris/pages/player/control_bar/volume_control.dart';
import 'package:iris/utils/exit_app.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/picture_in_picture.dart';
import 'package:iris/utils/platform.dart';
import 'package:iris/utils/take_screenshot.dart';
import 'package:iris/widgets/bottom_sheets/show_open_link_bottom_sheet.dart';
import 'package:iris/widgets/dialogs/show_choice_dialog.dart';
import 'package:iris/widgets/dialogs/show_open_link_dialog.dart';
import 'package:iris/widgets/dialogs/show_rotate_dialog.dart';
import 'package:iris/widgets/dialogs/show_shortcuts_dialog.dart';
import 'package:iris/widgets/dialogs/show_zoom_dialog.dart';
import 'package:iris/widgets/panel.dart';
import 'package:iris/widgets/refresh_playlist_action.dart';
import 'package:iris/widgets/popup.dart';
import 'package:iris/widgets/popups/history.dart';
import 'package:iris/widgets/popups/settings/settings.dart';
import 'package:iris/widgets/popups/storages/storages.dart';
import 'package:iris/widgets/popups/track/track_panel.dart';
import 'package:provider/provider.dart';

/// 「更多」菜单。
///
/// 一份动作列表，两种呈现：
/// - 窄屏 (< 600): 底部 sheet，拇指够得到，一行一件事；
/// - 宽屏: 锚在按钮上的 popup 菜单，带快捷键提示。
///
/// 以前是 15 项平铺在一个 popup 里，控制栏第二排还另外摆着刷新 / 横竖屏 /
/// 短视频三个入口。现在控制栏第二排固定五个位置（画面适配 / 存储 / 队列 /
/// 短视频 / 更多），两边**互为补集**：已经占位的动作这里不再重复，让位的
/// 动作（窄屏的音量）补进来。判定用的是控制栏传进来的同一个宽度 ——
/// 系统小窗里窗口比盒子宽时，两边不会各算各的。
class MoreMenuButton extends HookWidget {
  const MoreMenuButton({
    super.key,
    required this.file,
    required this.width,
    required this.hasVideos,
    required this.showControl,
    required this.showControlForHover,
    required this.onEnterShortVideo,
    this.color,
    this.overlayColor,
  });

  final FileItem? file;
  final double width;
  final bool hasVideos;
  final void Function() showControl;
  final Future<void> Function(Future<void> callback) showControlForHover;
  final VoidCallback onEnterShortVideo;
  final Color? color;
  final WidgetStateProperty<Color?>? overlayColor;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final rate = useAppStore().select(context, (state) => state.rate);
    final isFullScreen = usePlayerUiStore().select(
      context,
      (state) => state.isFullScreen,
    );
    final zoom = usePlayerUiStore().select(context, (state) => state.zoom);
    final bool pictureInPicture = useAppStore().select(
      context,
      (state) => state.pictureInPicture,
    );
    final double aspectRatio = usePlayerUiStore().select(
      context,
      (state) => state.aspectRatio,
    );
    final ScreenOrientation screenOrientation = useAppStore().select(
      context,
      (state) => state.orientation,
    );
    final int volume = useAppStore().select(context, (state) => state.volume);
    final bool isMuted =
        useAppStore().select(context, (state) => state.isMuted);
    final orientationLabels = {
      ScreenOrientation.device: t.device,
      ScreenOrientation.landscape: t.landscape,
      ScreenOrientation.portrait: t.portrait,
    };

    final groups = <_MoreGroup>[
      _MoreGroup(
        label: t.menu_open,
        icon: Icons.folder_open_rounded,
        actions: [
          _MoreAction(
            icon: Icons.file_open_rounded,
            label: t.open_file,
            shortcut: 'Ctrl + O',
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
          _MoreAction(
            icon: Icons.link_rounded,
            label: t.open_link,
            shortcut: 'Ctrl + L',
            onTap: () async {
              showControl();
              if (isDesktop) {
                await showOpenLinkDialog(context);
              } else {
                await showOpenLinkBottomSheet(context);
              }
              showControl();
            },
          ),
          // 两行布局里「存储」已经占控制栏第二个位置；桌面单行没有它，才在这里给。
          if (width >= 1200)
            _MoreAction(
              icon: Icons.storage_rounded,
              label: t.storage,
              shortcut: 'F',
              onTap: () => showControlForHover(
                showPopup(
                  context: context,
                  child: const Storages(),
                  direction: PopupDirection.right,
                ),
              ),
            ),
        ],
      ),
      _MoreGroup(
        label: t.menu_view,
        icon: Icons.tune_rounded,
        actions: [
          if (file?.type == ContentType.video)
            _MoreAction(
              icon: Icons.photo_camera_rounded,
              label: t.screenshot,
              shortcut: 'Ctrl + S',
              onTap: () async {
                showControl();
                await takeScreenshot(context, context.read<MediaPlayer>());
                showControl();
              },
            ),
          if (file?.type == ContentType.video)
            _MoreAction(
              icon: Icons.screen_rotation_alt_rounded,
              label: t.rotate,
              shortcut: 'Ctrl + T',
              onTap: () => showControlForHover(showRotateDialog(context)),
            ),
          if (file?.type != ContentType.audio)
            _MoreAction(
              icon: Icons.zoom_in_rounded,
              label: t.zoom,
              value: '${(zoom * 100).round()}%',
              onTap: () => showControlForHover(showZoomDialog(context)),
            ),
          if (file?.type == ContentType.video &&
              PictureInPicture.isSupported &&
              pictureInPicture)
            _MoreAction(
              icon: Icons.picture_in_picture_alt_rounded,
              label: t.enter_picture_in_picture,
              onTap: () {
                showControl();
                unawaited(PictureInPicture.enter(aspectRatio: aspectRatio));
              },
            ),
          if (!isDesktop)
            _MoreAction(
              icon: Icons.screen_rotation_rounded,
              label: t.screen_orientation,
              value:
                  orientationLabels[screenOrientation] ??
                  screenOrientation.name,
              onTap: () => showControlForHover(
                showOrientationDialog(context, value: screenOrientation),
              ),
            ),
          if (isDesktop)
            _MoreAction(
              icon: isFullScreen
                  ? Icons.close_fullscreen_rounded
                  : Icons.open_in_full_rounded,
              label: isFullScreen ? t.exit_fullscreen : t.enter_fullscreen,
              onTap: () => usePlayerUiStore().updateFullScreen(!isFullScreen),
            ),
        ],
      ),
      _MoreGroup(
        label: t.menu_playback,
        icon: Icons.play_circle_outline_rounded,
        actions: [
          _MoreAction(
            icon: Icons.speed_rounded,
            label: t.playback_speed,
            value: '${rate}X',
            onTap: () =>
                showControlForHover(showRateDialog(context, value: rate)),
          ),
          _MoreAction(
            icon: Icons.graphic_eq_rounded,
            label: t.audio_track,
            shortcut: 'S',
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
          // 两行布局里音量不再占控制栏，改从这里进。
          // 桌面单行仍在进度条左边保留滑条，所以那边不重复给入口。
          if (width < 1200)
            _MoreAction(
              icon: isMuted || volume == 0
                  ? Icons.volume_off_rounded
                  : volume < 50
                      ? Icons.volume_down_rounded
                      : Icons.volume_up_rounded,
              label: t.volume,
              value: isMuted ? t.mute : '$volume',
              onTap: () => showControlForHover(
                showVolumeDialog(context, showControl),
              ),
            ),
          if (hasVideos && width >= 1200)
            _MoreAction(
              icon: Icons.swipe_vertical_rounded,
              label: t.short_video_mode,
              onTap: onEnterShortVideo,
            ),
          _MoreAction(
            icon: Icons.refresh_rounded,
            label: t.refresh_play_queue,
            onTap: () {
              showControl();
              unawaited(refreshPlaylistWithFeedback(context));
            },
          ),
          _MoreAction(
            icon: Icons.monitor_heart_rounded,
            label: t.playback_stats,
            shortcut: 'Ctrl + I',
            onTap: () {
              usePlayerUiStore().toggleIsShowStats();
              showControl();
            },
          ),
        ],
      ),
      _MoreGroup(
        label: t.menu_app,
        icon: Icons.apps_rounded,
        actions: [
          if (isDesktop)
            _MoreAction(
              icon: Icons.keyboard_rounded,
              label: t.shortcuts,
              onTap: () => showControlForHover(showShortcutsDialog(context)),
            ),
          _MoreAction(
            icon: Icons.history_rounded,
            label: t.history,
            shortcut: 'Ctrl + H',
            onTap: () => showControlForHover(
              showPopup(
                context: context,
                child: const History(),
                direction: PopupDirection.right,
              ),
            ),
          ),
          _MoreAction(
            icon: Icons.settings_rounded,
            label: t.settings,
            shortcut: 'Ctrl + P',
            onTap: () => showControlForHover(
              showPopup(
                context: context,
                child: const Settings(),
                direction: PopupDirection.right,
              ),
            ),
          ),
          _MoreAction(
            icon: Icons.exit_to_app_rounded,
            label: t.exit,
            shortcut: 'Alt + X',
            onTap: () async {
              await exitApp(context.read<MediaPlayer>());
            },
          ),
        ],
      ),
    ];

    final icon = Icon(Icons.more_vert_rounded, size: 20, color: color);

    final bool useSheet = width < 600;

    // 每个按钮持有自己的控制器: 全局共享的话, 小窗 / 分屏里同时存在两个
    // 控制栏时会互相抢 anchor。
    final menuController = useMemoized(() => MenuController(), []);

    // 键盘 / 右键菜单键只认这一个入口: 按当前布局注册一次, 每次读最新的动作表。
    final groupsRef = useRef<List<_MoreGroup>>(groups);
    groupsRef.value = groups;
    useEffect(() {
      final VoidCallback callback = useSheet
          ? () => _showSheet(context, groupsRef.value)
          : () => menuController.open();
      openMoreMenu = callback;
      return () {
        // 只在仍指向自己时清空: 路由交接时旧实例的 dispose 不能把新的入口抹掉。
        if (identical(openMoreMenu, callback)) openMoreMenu = null;
      };
    }, [useSheet]);

    if (useSheet) {
      return IconButton(
        tooltip: t.more_options,
        icon: icon,
        style: ButtonStyle(overlayColor: overlayColor),
        onPressed: () => _showSheet(context, groups),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final menuStyle = MenuStyle(
      backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainer),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      elevation: const WidgetStatePropertyAll(0),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 8)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
    );

    return MenuAnchor(
      controller: menuController,
      style: menuStyle,
      menuChildren: [
        for (final group in groups)
          if (group.actions.isNotEmpty)
            SubmenuButton(
              menuStyle: menuStyle,
              leadingIcon: Icon(group.icon, size: 20),
              submenuIcon: const WidgetStatePropertyAll(
                Icon(Icons.chevron_right_rounded, size: 18),
              ),
              style: const ButtonStyle(
                padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 12),
                ),
                minimumSize: WidgetStatePropertyAll(Size(220, 44)),
                alignment: Alignment.centerLeft,
              ),
              menuChildren: [
                for (final action in group.actions)
                  MenuItemButton(
                    leadingIcon: Icon(action.icon, size: 20),
                    trailingIcon:
                        action.value == null && action.shortcut == null
                        ? null
                        : Text(
                            action.value ?? action.shortcut!,
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                    onPressed: action.onTap,
                    child: Text(action.label),
                  ),
              ],
              child: Text(group.label),
            ),
      ],
      builder: (context, controller, child) => IconButton(
        tooltip: t.more_options,
        icon: icon,
        style: ButtonStyle(overlayColor: overlayColor),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }

  Future<void> _showSheet(BuildContext context, List<_MoreGroup> groups) async {
    final t = getLocalizations(context);
    final scheme = Theme.of(context).colorScheme;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.82,
          ),
          child: PanelSurface(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                PanelHeader(title: Text(t.more_options)),
                const PanelDivider(),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final group in groups)
                          if (group.actions.isNotEmpty)
                            PanelSection(
                              children: [
                                for (final action in group.actions)
                                  _MoreSheetRow(
                                    action: action,
                                    isDesktop: isDesktop,
                                    onTap: () {
                                      Navigator.of(sheetContext).pop();
                                      WidgetsBinding.instance
                                          .addPostFrameCallback(
                                            (_) => action.onTap(),
                                          );
                                    },
                                  ),
                              ],
                            ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MoreGroup {
  const _MoreGroup({
    required this.label,
    required this.icon,
    required this.actions,
  });

  final String label;
  final IconData icon;
  final List<_MoreAction> actions;
}

class _MoreAction {
  const _MoreAction({
    required this.icon,
    required this.label,
    this.value,
    this.shortcut,
    required this.onTap,
  });

  final IconData icon;
  final String label;

  /// 当前值 (倍速 / 方向 / 缩放)，窄屏也显示。
  final String? value;

  /// 键盘快捷键，只在桌面显示。
  final String? shortcut;

  final VoidCallback onTap;
}

/// sheet 里的一行。当前值在窄屏也显示，快捷键只在桌面显示。
class _MoreSheetRow extends StatelessWidget {
  const _MoreSheetRow({
    required this.action,
    required this.isDesktop,
    required this.onTap,
  });

  final _MoreAction action;
  final bool isDesktop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final trailing = action.value ?? (isDesktop ? action.shortcut : null);
    final scheme = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      minVerticalPadding: 8,
      leading: Icon(action.icon, size: 20),
      title: Text(action.label, style: Theme.of(context).textTheme.bodyLarge),
      trailing: trailing == null
          ? null
          : Text(
              trailing,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
      onTap: onTap,
    );
  }
}
