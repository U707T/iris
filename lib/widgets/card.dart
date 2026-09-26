import 'dart:ui';
import 'package:material_ui/material_ui.dart';

class Card extends StatelessWidget {
  const Card({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius,
    this.color,
    this.border,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final Color? color;
  final Border? border;

  @override
  Widget build(BuildContext context) {
    final effectiveBorderRadius = borderRadius ?? BorderRadius.circular(16);
    final effectiveBorder = border ??
        Border.all(
          color: Theme.of(context)
              .colorScheme
              .onSurfaceVariant
              .withValues(alpha: 0.125),
          width: 1,
        );

    return Stack(
      children: [
        ClipRRect(
          borderRadius: effectiveBorderRadius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: padding ?? const EdgeInsets.all(0),
              decoration: BoxDecoration(
                borderRadius: effectiveBorderRadius,
                color: color ??
                    Theme.of(context)
                        .colorScheme
                        .surfaceContainer
                        .withValues(alpha: 0.75),
              ),
              child: child,
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: effectiveBorderRadius,
                border: effectiveBorder,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
