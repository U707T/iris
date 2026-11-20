import 'package:material_ui/material_ui.dart';
import 'package:iris/utils/platform.dart';

/// 文件 / 队列 / 历史共用的一行媒体条目。
///
/// 三种列表以前各写一遍：标题最多三行、大小和日期挤在一行、进度做成一个
/// 彩色小胶囊。结果是同一个文件在「存储」里和「播放队列」里长得不一样，
/// 而三处都在算同一个百分比。
///
/// 现在统一成：图标 + 一行标题 + 一行灰色元信息 + 右侧灰色百分比 + 菜单。
/// 标题只占一行 —— 文件名再长也不该把列表撑成三行；完整名字在悬停提示里。
class MediaRow extends StatelessWidget {
  const MediaRow({
    super.key,
    required this.icon,
    required this.title,
    this.meta,
    this.progress,
    this.menu,
    this.onTap,
    this.selected = false,
    this.focusNode,
    this.autofocus = false,
  });

  final IconData icon;
  final String title;

  /// 灰色元信息：大小、日期。为 null 时整行只有标题。
  final String? meta;

  /// 播放进度，例如 `42%`。纯文本，不再画成胶囊。
  final String? progress;

  final Widget? menu;
  final VoidCallback? onTap;

  /// 当前正在播放的那一条。
  final bool selected;

  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListTile(
      focusNode: focusNode,
      autofocus: autofocus,
      selected: selected,
      selectedTileColor: scheme.primary.withValues(alpha: 0.08),
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
      visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
      leading: SizedBox(
        width: 24,
        child: Center(
          child: Icon(icon, size: 20, color: scheme.onSurfaceVariant),
        ),
      ),
      title: _title(context, scheme),
      subtitle: meta == null
          ? null
          : Text(
              meta!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
      trailing: (progress == null && menu == null)
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (progress != null)
                  Text(
                    progress!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ?menu,
              ],
            ),
      onTap: onTap,
    );
  }

  /// 标题只占一行，完整文件名在桌面端悬停时给出。
  ///
  /// Tooltip 只在桌面包一层：它在触屏上默认是长按触发，会把列表项本来要接的
  /// 长按吃掉（手机上弹出一个文件名气泡，比看不到全名更烦）。
  Widget _title(BuildContext context, ColorScheme scheme) {
    final text = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
        color: selected ? scheme.primary : null,
        fontWeight: selected ? FontWeight.w600 : null,
      ),
    );

    if (!isDesktop) return text;
    return Tooltip(
      message: title,
      waitDuration: const Duration(milliseconds: 600),
      child: text,
    );
  }
}
