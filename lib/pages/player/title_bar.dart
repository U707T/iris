import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/info.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/platform.dart';
import 'package:window_manager/window_manager.dart';

class TitleBar extends HookWidget {
  const TitleBar({
    super.key,
    this.title,
    this.actions,
    this.color,
    this.overlayColor,
    this.saveProgress,
  });

  final String? title;
  final List<Widget>? actions;
  final Color? color;
  final WidgetStateProperty<Color?>? overlayColor;
  final Future<void> Function()? saveProgress;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final isAlwaysOnTop =
        usePlayerUiStore().select(context, (state) => state.isAlwaysOnTop);
    final isFullScreen =
        usePlayerUiStore().select(context, (state) => state.isFullScreen);

    // 窗口最大化状态必须跟着系统事件走: 以前在 build 里现开一个 FutureBuilder,
    // 只会在首帧查一次, 最大化后图标和按钮闭包都停在旧值, 再点也无法还原。
    final isMaximized = useState(false);
    final windowListener = useMemoized(() => _TitleBarWindowListener(), []);

    useEffect(() {
      if (!isDesktop) return null;

      var alive = true;
      Future<void> sync() async {
        try {
          final value = await windowManager.isMaximized();
          if (alive) isMaximized.value = value;
        } catch (_) {}
      }

      windowListener.onChange = sync;
      windowManager.addListener(windowListener);
      sync();

      return () {
        alive = false;
        windowListener.onChange = null;
        windowManager.removeListener(windowListener);
      };
    }, [windowListener]);

    return Container(
      padding: isDesktop
          ? const EdgeInsets.fromLTRB(12, 4, 4, 8)
          : const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black87.withValues(alpha: 0.6),
            Colors.black87.withValues(alpha: 0.25),
            Colors.black87.withValues(alpha: 0),
          ],
        ),
      ),
      child: ExcludeFocus(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/logo_transparent.png',
              width: 32,
              height: 32,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title!.isEmpty ? INFO.title : title!,
                maxLines: 1,
                textAlign: TextAlign.start,
                style: TextStyle(
                  fontSize: 16,
                  overflow: TextOverflow.ellipsis,
                  color: color,
                ),
              ),
            ),
            Row(
              children: [
                ...actions ?? [],
                if (isDesktop) ...[
                  Visibility(
                    visible: !isFullScreen,
                    child: IconButton(
                      tooltip: isAlwaysOnTop
                          ? '${t.always_on_top_on} ( F10 )'
                          : '${t.always_on_top_off} ( F10 )',
                      icon: Icon(
                        isAlwaysOnTop
                            ? Icons.push_pin_rounded
                            : Icons.push_pin_outlined,
                        size: 18,
                        color: color,
                      ),
                      onPressed: usePlayerUiStore().toggleIsAlwaysOnTop,
                      style: ButtonStyle(overlayColor: overlayColor),
                    ),
                  ),
                  Visibility(
                    visible: isFullScreen,
                    child: IconButton(
                      tooltip: isFullScreen
                          ? '${t.exit_fullscreen} ( Escape, F11, Enter )'
                          : '${t.enter_fullscreen} ( F11, Enter )',
                      icon: Icon(
                        isFullScreen
                            ? Icons.close_fullscreen_rounded
                            : Icons.open_in_full_rounded,
                        size: 18,
                        color: color,
                      ),
                      onPressed: () async {
                        usePlayerUiStore().updateFullScreen(!isFullScreen);
                      },
                      style: ButtonStyle(overlayColor: overlayColor),
                    ),
                  ),
                  Visibility(
                    visible: !isFullScreen,
                    child: IconButton(
                      onPressed: () => windowManager.minimize(),
                      icon: Icon(
                        Icons.remove_rounded,
                        color: color,
                      ),
                      style: ButtonStyle(overlayColor: overlayColor),
                    ),
                  ),
                  Visibility(
                    visible: !isFullScreen,
                    child: IconButton(
                      onPressed: () async {
                        if (isMaximized.value) {
                          await windowManager.unmaximize();
                        } else {
                          await windowManager.maximize();
                        }
                      },
                      icon: isMaximized.value
                          ? RotatedBox(
                              quarterTurns: 2,
                              child: Icon(
                                Icons.filter_none_rounded,
                                size: 18,
                                color: color,
                              ),
                            )
                          : Icon(
                              Icons.crop_din_rounded,
                              size: 20,
                              color: color,
                            ),
                      style: ButtonStyle(overlayColor: overlayColor),
                    ),
                  ),
                  IconButton(
                    onPressed: () async {
                      await saveProgress?.call();
                      windowManager.close();
                    },
                    icon: Icon(
                      Icons.close_rounded,
                      color: color,
                    ),
                    style: ButtonStyle(
                      overlayColor: WidgetStateProperty.resolveWith<Color?>(
                          (Set<WidgetState> states) {
                        if (states.contains(WidgetState.pressed)) {
                          return Colors.red.withValues(alpha: 0.4);
                        } else if (states.contains(WidgetState.hovered)) {
                          return Colors.red.withValues(alpha: 0.5);
                        }
                        return null;
                      }),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 只关心「最大化状态可能变了」的窗口事件，避免整个标题栏订阅所有窗口回调。
class _TitleBarWindowListener extends WindowListener {
  VoidCallback? onChange;

  @override
  void onWindowMaximize() => onChange?.call();

  @override
  void onWindowUnmaximize() => onChange?.call();

  @override
  void onWindowRestore() => onChange?.call();

  @override
  void onWindowFocus() => onChange?.call();
}
