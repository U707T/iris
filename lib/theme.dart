import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart' as legacy; // google_fonts 尚未迁移, 仅用于 TextTheme 转换
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';

/// google_fonts 仍基于 SDK 旧版 Material (`package:flutter/material.dart`),
/// 与 material_ui 的 TextTheme 是不同类型 (TextStyle 本身共用)。
/// 以下两个函数在两边之间搬运文本样式。
legacy.TextTheme _toLegacyTextTheme(TextTheme t) => legacy.TextTheme(
      displayLarge: t.displayLarge,
      displayMedium: t.displayMedium,
      displaySmall: t.displaySmall,
      headlineLarge: t.headlineLarge,
      headlineMedium: t.headlineMedium,
      headlineSmall: t.headlineSmall,
      titleLarge: t.titleLarge,
      titleMedium: t.titleMedium,
      titleSmall: t.titleSmall,
      bodyLarge: t.bodyLarge,
      bodyMedium: t.bodyMedium,
      bodySmall: t.bodySmall,
      labelLarge: t.labelLarge,
      labelMedium: t.labelMedium,
      labelSmall: t.labelSmall,
    );

TextTheme _fromLegacyTextTheme(legacy.TextTheme t) => TextTheme(
      displayLarge: t.displayLarge,
      displayMedium: t.displayMedium,
      displaySmall: t.displaySmall,
      headlineLarge: t.headlineLarge,
      headlineMedium: t.headlineMedium,
      headlineSmall: t.headlineSmall,
      titleLarge: t.titleLarge,
      titleMedium: t.titleMedium,
      titleSmall: t.titleSmall,
      bodyLarge: t.bodyLarge,
      bodyMedium: t.bodyMedium,
      bodySmall: t.bodySmall,
      labelLarge: t.labelLarge,
      labelMedium: t.labelMedium,
      labelSmall: t.labelSmall,
    );

ThemeData baseTheme(BuildContext context) {
  return ThemeData(
    popupMenuTheme: PopupMenuThemeData(
      menuPadding: const EdgeInsets.all(0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      shadowColor: null,
      elevation: 0,
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
  );
}

ColorScheme customColorScheme =
    ColorScheme.fromSeed(seedColor: const Color(0xFFB3BCDF));
ColorScheme customDarkColorScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFFB3BCDF), brightness: Brightness.dark);

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
  ColorScheme colorScheme =
      lightDynamic != null ? lightDynamic.harmonized() : customColorScheme;
  ColorScheme darkColorScheme =
      darkDynamic != null ? darkDynamic.harmonized() : customDarkColorScheme;

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

  final base = baseTheme(context);

  final lightTheme = ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    textTheme: _fromLegacyTextTheme(GoogleFonts.notoSansScTextTheme()),
    popupMenuTheme: base.popupMenuTheme,
    dropdownMenuTheme: base.dropdownMenuTheme,
    listTileTheme: base.listTileTheme,
  );

  final darkTheme = ThemeData.dark(useMaterial3: true).copyWith(
    colorScheme: darkColorScheme,
    scaffoldBackgroundColor: pureBlack ? Colors.black : null,
    textTheme: _fromLegacyTextTheme(
      GoogleFonts.notoSansScTextTheme(
        _toLegacyTextTheme(
          ThemeData.dark(useMaterial3: true)
              .copyWith(colorScheme: darkColorScheme)
              .textTheme,
        ),
      ),
    ),
    popupMenuTheme: base.popupMenuTheme,
    dropdownMenuTheme: base.dropdownMenuTheme,
    listTileTheme: base.listTileTheme,
  );

  return CustomTheme(light: lightTheme, dark: darkTheme);
}
