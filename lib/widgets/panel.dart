import 'package:material_ui/material_ui.dart';
import 'package:iris/utils/get_localizations.dart';

/// 浮层面板的统一骨架。
///
/// 一个面板只有三件事：顶部一行标题栏、一条发丝分隔线、剩下全是内容。
/// 标题栏里标题在左、操作在右、关闭永远在最右；面板本身不投影、不透明 ——
/// 播放器上的浮层要的是可读，不是玻璃。
///
/// 以前每个面板各写一遍标题 / 底栏：设置和存储在**底部**再重复一次标题，
/// 历史和队列把标题和关闭放在底部工具条里。同一个动作在四个面板里长得不
/// 一样，改一处就要翻四个文件。现在只有这里定义一次。

/// 面板标题栏。高度固定 48，标题可以是文字，也可以是 TabBar（设置 / 存储）。
class PanelHeader extends StatelessWidget {
  const PanelHeader({
    super.key,
    this.title,
    this.actions = const [],
    this.showClose = true,
  });

  final Widget? title;
  final List<Widget> actions;
  final bool showClose;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);

    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: DefaultTextStyle.merge(
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                child: title ?? const SizedBox.shrink(),
              ),
            ),
          ),
          ...actions,
          if (showClose)
            IconButton(
              tooltip: '${t.close} ( Escape )',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: () => Navigator.of(context).pop(),
            ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

/// 面板里的发丝分隔线。用 outlineVariant，而不是主题色 —— 分隔线不是强调。
class PanelDivider extends StatelessWidget {
  const PanelDivider({super.key});

  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    thickness: 1,
    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
  );
}

/// 设置项分组：一组行放在一块圆角底色里，组与组之间靠留白分开。
///
/// 分组不靠标题，靠布局 —— 多一行「通用」「播放」的小字，就是在用文字
/// 弥补布局没做好的事。
class PanelSection extends StatelessWidget {
  const PanelSection({
    super.key,
    required this.children,
    this.margin = const EdgeInsets.fromLTRB(12, 0, 12, 8),
  });

  final List<Widget> children;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    // 用 Material 而不是带底色的 Container: ListTile 的水波纹画在最近的
    // Material 上, 中间隔一层有底色的 DecoratedBox 会把水波纹整个盖掉
    // (debug 下还会直接报错)。
    return Padding(
      padding: margin,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

/// 面板的底板：不透明、发丝边框、无模糊。
///
/// 播放器上的浮层底下永远是画面，半透明 + 高斯模糊只会让字更难读，还要为
/// 每一帧付一次 BackdropFilter 的代价。纯色底反而更干净、更省。
class PanelSurface extends StatelessWidget {
  const PanelSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
  });

  final Widget child;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surfaceContainer,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: child,
    );
  }
}

/// 空状态：一行灰字，不画插画、不写解释。
class PanelEmpty extends StatelessWidget {
  const PanelEmpty({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      label,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
