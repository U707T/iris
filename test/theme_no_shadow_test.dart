import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/theme.dart';

/// 全应用"浮层不投影"的约定。
///
/// 播放器的底色永远是画面本身: 菜单 / 对话框 / 提示条每带一条阴影, 在小窗和
/// 横屏下就是画面中间糊一圈灰边 (MIUI / HyperOS 小窗最明显 —— 窗口小、背景亮,
/// 阴影比内容还显眼)。
///
/// 这条约定必须**在主题层**成立, 不能靠逐处 `elevation: 0`: 浮层实际的阴影取
/// 自 `colorScheme.shadow`, 逐处 call site 漏一个就回来一条。
void main() {
  final theme = getTheme(
    context: _FakeContext(),
    lightDynamic: null,
    darkDynamic: null,
  );

  for (final entry in <String, ThemeData>{
    'light': theme.light,
    'dark': theme.dark,
  }.entries) {
    group('${entry.key} 主题', () {
      final t = entry.value;

      test('colorScheme.shadow 透明 (M3 浮层阴影的真正来源)', () {
        expect(t.colorScheme.shadow, Colors.transparent);
        expect(t.colorScheme.shadow.a, 0);
      });

      test('ThemeData.shadowColor 透明 (非 M3 路径)', () {
        expect(t.shadowColor, Colors.transparent);
      });

      test('每个自带 elevation 的组件主题都是 0', () {
        expect(t.popupMenuTheme.elevation, 0);
        expect(t.dialogTheme.elevation, 0);
        expect(t.snackBarTheme.elevation, 0);
        expect(t.bottomSheetTheme.elevation, 0);
        expect(t.bottomSheetTheme.modalElevation, 0);
      });

      test('浮层自己声明的 shadowColor / surfaceTintColor 也透明', () {
        expect(t.popupMenuTheme.shadowColor, Colors.transparent);
        expect(t.dialogTheme.shadowColor, Colors.transparent);
        expect(t.dialogTheme.surfaceTintColor, Colors.transparent);
        expect(t.bottomSheetTheme.shadowColor, Colors.transparent);
        expect(t.bottomSheetTheme.surfaceTintColor, Colors.transparent);
      });
    });
  }

  test('动态取色 (系统配色) 时同样没有阴影', () {
    // 动态取色会把 colorScheme 整体换掉: 若只在自定义配色上 copyWith,
    // 这里就会漏。
    final dynamic = ColorScheme.fromSeed(seedColor: Colors.red);
    final t = getTheme(
      context: _FakeContext(),
      lightDynamic: dynamic,
      darkDynamic: dynamic,
    );
    expect(t.light.colorScheme.shadow, Colors.transparent);
    expect(t.dark.colorScheme.shadow, Colors.transparent);
  });

  test('纯黑主题 (OLED) 也一样', () {
    final t = getTheme(
      context: _FakeContext(),
      lightDynamic: null,
      darkDynamic: null,
      pureBlack: true,
    );
    expect(t.dark.colorScheme.shadow, Colors.transparent);
    expect(t.dark.colorScheme.surface, Colors.black);
    expect(t.dark.snackBarTheme.elevation, 0);
  });
}

/// [getTheme] 只把 context 透传给 [baseTheme], 而 baseTheme 不用它 ——
/// 这里给一个不依赖树的空实现, 免得为了测主题去搭 Widget 环境。
class _FakeContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
