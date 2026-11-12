import 'package:dynamic_color/dynamic_color.dart';
import 'package:material_ui/material_ui.dart';

/// 全应用的浮层一律**不投影**。
///
/// 播放器的底色永远是画面本身, 上面浮着的菜单 / 对话框 / 提示条一旦带阴影,
/// 在小窗和横屏下就是在画面中间糊一圈灰边 —— 尤其 MIUI / HyperOS 的小窗,
/// 窗口小、背景亮, 阴影比内容还显眼。
///
/// 逐处 `elevation: 0` 治不住: 真正落影的是 [ColorScheme.shadow] (M3 每个浮层
/// 组件在自己的 defaults 里各取一遍, 例如 PopupMenu 的
/// `shadowColor => _colors.shadow`), 漏一个就回来一条。所以在主题层把它设成
/// 透明, 逐处 call site 就不用再各写一遍。
const Color _noShadow = Colors.transparent;

/// 与阴影无关的浮层形状 (圆角 / 内边距)。
PopupMenuThemeData _popupMenuTheme() => PopupMenuThemeData(
  menuPadding: const EdgeInsets.all(0),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  shadowColor: _noShadow,
  elevation: 0,
);

ListTileThemeData _listTileTheme() => ListTileThemeData(
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
);

/// 把"无阴影"约定套到一份具体配色的主题上。
///
/// shadow 必须来自**当前**配色: 动态取色一开, colorScheme 会被整体换成系统
/// 色, 里面的 shadow 又变回黑色 —— 所以这里统一 copyWith 一次, 而不是在
/// `ThemeData` 构造时写死。
ThemeData _applyNoShadow(
  ThemeData theme, {
  required ColorScheme colorScheme,
  bool pureBlack = false,
}) {
  return theme.copyWith(
    colorScheme: colorScheme.copyWith(shadow: _noShadow),
    shadowColor: _noShadow,
    popupMenuTheme: _popupMenuTheme(),
    listTileTheme: _listTileTheme(),
    dialogTheme: theme.dialogTheme.copyWith(
      elevation: 0,
      shadowColor: _noShadow,
      surfaceTintColor: _noShadow,
    ),
    snackBarTheme: theme.snackBarTheme.copyWith(elevation: 0),
    bottomSheetTheme: theme.bottomSheetTheme.copyWith(
      elevation: 0,
      modalElevation: 0,
      shadowColor: _noShadow,
      surfaceTintColor: _noShadow,
    ),
    scaffoldBackgroundColor: pureBlack && theme.brightness == Brightness.dark
        ? Colors.black
        : theme.scaffoldBackgroundColor,
  );
}

ColorScheme customColorScheme = ColorScheme.fromSeed(
  seedColor: const Color(0xFFB3BCDF),
);
ColorScheme customDarkColorScheme = ColorScheme.fromSeed(
  seedColor: const Color(0xFFB3BCDF),
  brightness: Brightness.dark,
);

class CustomTheme {
  final ThemeData light;
  final ThemeData dark;

  CustomTheme({required this.light, required this.dark});
}

CustomTheme getTheme({
  required BuildContext context,
  required ColorScheme? lightDynamic,
  required ColorScheme? darkDynamic,
  bool pureBlack = false,
}) {
  ColorScheme colorScheme = lightDynamic != null
      ? lightDynamic.harmonized()
      : customColorScheme;
  ColorScheme darkColorScheme = darkDynamic != null
      ? darkDynamic.harmonized()
      : customDarkColorScheme;

  // OLED 纯黑主题: 暗色模式下使用纯黑背景, 更适合 OLED 屏幕
  if (pureBlack) {
    darkColorScheme = darkColorScheme.copyWith(
      surface: Colors.black,
      surfaceContainerLowest: Colors.black,
      surfaceContainerLow: Colors.black,
      surfaceContainer: const Color(0xFF0A0A0A),
      surfaceContainerHigh: const Color(0xFF121212),
      surfaceContainerHighest: const Color(0xFF1A1A1A),
    );
  }

  final lightTheme = _applyNoShadow(
    ThemeData(colorScheme: colorScheme, useMaterial3: true),
    colorScheme: colorScheme,
  );

  final darkTheme = _applyNoShadow(
    ThemeData.dark(useMaterial3: true),
    colorScheme: darkColorScheme,
    pureBlack: pureBlack,
  );

  return CustomTheme(light: lightTheme, dark: darkTheme);
}
