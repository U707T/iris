import 'package:material_ui/material_ui.dart';
import 'package:iris/models/storages/local.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/platform.dart';
import 'package:iris/widgets/bottom_sheets/show_open_link_bottom_sheet.dart';
import 'package:iris/widgets/dialogs/show_open_link_dialog.dart';
import 'package:iris/widgets/popup.dart';
import 'package:iris/widgets/popups/history.dart';
import 'package:iris/widgets/popups/settings/settings.dart';
import 'package:iris/widgets/popups/storages/storages.dart';

/// 没有媒体时的主界面。
///
/// 以前这里是一条完整的控制栏：00:00 / 00:00 的进度条、按了没反应的播放键、
/// 置灰的随机 / 循环，再加一排工具按钮。空屏上摆一套不能用的控件，不是
/// 「功能齐全」，是没做空状态。
///
/// 现在只有三个层次：一个淡图标、一个主操作（打开文件）、一个次操作
/// （打开链接）；存储 / 历史 / 设置沉到底部，拇指够得到，也不抢主操作。
class EmptyPlayer extends StatelessWidget {
  const EmptyPlayer({super.key});

  Future<void> _openFile() async {
    if (isAndroid) {
      await pickContentFile();
    } else {
      await pickLocalFile();
    }
  }

  Future<void> _openLink(BuildContext context) async {
    if (isDesktop) {
      await showOpenLinkDialog(context);
    } else {
      await showOpenLinkBottomSheet(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);

    return Column(
      children: [
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.play_circle_outline_rounded,
                  size: 56,
                  color: Colors.white24,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: 200,
                  child: FilledButton.icon(
                    onPressed: _openFile,
                    icon: const Icon(Icons.folder_open_rounded, size: 18),
                    label: Text(
                      t.open_file,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: Colors.black,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      minimumSize: const Size.fromHeight(44),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: 200,
                  child: TextButton.icon(
                    onPressed: () => _openLink(context),
                    icon: const Icon(Icons.link_rounded, size: 18),
                    label: Text(t.open_link),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white70,
                      minimumSize: const Size.fromHeight(40),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _EmptyAction(
                  label: t.storage,
                  onPressed: () => showPopup(
                    context: context,
                    child: const Storages(),
                    direction: PopupDirection.right,
                  ),
                ),
                _EmptyAction(
                  label: t.history,
                  onPressed: () => showPopup(
                    context: context,
                    child: const History(),
                    direction: PopupDirection.right,
                  ),
                ),
                _EmptyAction(
                  label: t.settings,
                  onPressed: () => showPopup(
                    context: context,
                    child: const Settings(),
                    direction: PopupDirection.right,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyAction extends StatelessWidget {
  const _EmptyAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: Colors.white54,
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white54,
              ),
        ),
      );
}
