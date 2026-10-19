import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/platform.dart';
import 'package:material_ui/material_ui.dart';

/// 空队列时的引导提示。
///
/// 首次启动 (或关掉当前文件后) 以前只有一片纯黑, 新用户不知道下一步做什么。
/// 这里给一个不拦截手势的提示: 拖入文件 / Ctrl+O / 手机上先点画面再点「打开文件」。
class EmptyPlayerHint extends StatelessWidget {
  const EmptyPlayerHint({super.key});

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final color = Colors.white.withValues(alpha: 0.45);

    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.movie_outlined, size: 56, color: color),
                const SizedBox(height: 16),
                Text(
                  isDesktop
                      ? t.empty_player_hint
                      : t.empty_player_hint_mobile,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    height: 1.5,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
