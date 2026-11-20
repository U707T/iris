import 'package:material_ui/material_ui.dart';

/// 设置里的一行：图标 + 名称 + 右侧的值 / 开关。
///
/// 只有一行。需要说明的选项不是靠下面再挂一行小字，而是靠标题本身说清楚，
/// 或者把当前值放到右侧（「快进/快退时长    5 秒」比「快进/快退时长」+
/// 副标题「5 秒」少一行、也更好扫）。确实说不清的选项，就不该做成一个选项。
///
/// [onTap] 与 [onToggle] 二选一：前者是「打开一个选择器」，后者是「开关」。
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.icon,
    required this.label,
    this.value,
    this.onTap,
    this.toggle,
    this.onToggle,
    this.enabled = true,
  }) : assert(
         (onTap == null) != (onToggle == null),
         'SettingRow 需要 onTap 或 onToggle 其中之一',
       );

  final IconData icon;
  final String label;

  /// 右侧当前值（语言、主题、时长……）。为 null 时不占位。
  final String? value;

  final VoidCallback? onTap;

  /// 开关状态。与 [onToggle] 一起使用。
  final bool? toggle;
  final ValueChanged<bool>? onToggle;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bool isToggle = onToggle != null;

    final Widget row = ListTile(
      enabled: enabled,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      minVerticalPadding: 10,
      leading: Icon(icon, size: 20, color: scheme.onSurfaceVariant),
      title: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      trailing: isToggle
          ? Switch.adaptive(
              value: toggle ?? false,
              onChanged: enabled ? onToggle : null,
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (value != null)
                  Text(
                    value!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                if (onTap != null && enabled)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
      onTap: enabled
          ? isToggle
                ? () => onToggle!(!(toggle ?? false))
                : onTap
          : null,
    );

    // 开关行整体读成一句「名称, 开关, 开 / 关」，而不是标题和开关各读一遍。
    return isToggle ? MergeSemantics(child: row) : row;
  }
}
