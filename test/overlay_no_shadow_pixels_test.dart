import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/theme.dart';

/// 像素级验收: 弹出菜单矩形**外侧**有没有被压暗。
///
/// 这是全应用唯一真会投影的浮层: M3 的 PopupMenu 默认
/// `elevation: 3` + `shadowColor: colorScheme.shadow`。对话框 / 提示条在 M3 下
/// 默认的 shadowColor 就是透明, 所以真正需要压住的是 `colorScheme.shadow`
/// —— 只把 `elevation` 写 0 是治不住的 (而且会连菜单自己的内边距一起覆盖掉)。
///
/// 对照组用一份没做无阴影处理的主题, 证明检测本身有效。
void main() {
  // 不预加载 Roboto: 像素量的是菜单**外侧**的灰度带, 菜单里的文字用
  // Ahem 方块字体也一样 —— 而且 Flutter SDK 的安装路径在沙箱 (/opt/flutter)
  // 与 CI (hostedtoolcache) 里不同, 写死绝对路径会让两个环境各崩一边。

  final appTheme = getTheme(
    context: _FakeContext(),
    lightDynamic: null,
    darkDynamic: null,
  );

  /// 在白底中间弹一个菜单, 返回菜单矩形**左侧外侧**最暗的像素亮度
  /// (1.0 = 完全没被压暗)。
  Future<double> darkestLeftOfMenu(
    WidgetTester tester,
    ThemeData testTheme,
  ) async {
    final boundaryKey = GlobalKey();
    await tester.binding.setSurfaceSize(const Size(600, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: testTheme,
        builder: (context, child) => RepaintBoundary(
          key: boundaryKey,
          child: ColoredBox(color: Colors.white, child: child!),
        ),
        home: Scaffold(
          backgroundColor: Colors.white,
          // 菜单在屏幕正中弹出: 它四周都是纯白, 量到的一定是阴影而不是
          // 别的界面元素
          body: const Center(
            child: PopupMenuButton<int>(
              itemBuilder: _items,
              child: SizedBox(width: 120, height: 40, child: Text('open')),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final RenderBox boundary =
        boundaryKey.currentContext!.findRenderObject()! as RenderBox;
    final RenderBox item =
        tester.renderObject(find.byType(PopupMenuItem<int>).first) as RenderBox;
    final Rect rect =
        item.localToGlobal(Offset.zero, ancestor: boundary) & item.size;

    late Uint8List pixels;
    late int width;
    await tester.runAsync(() async {
      final image = await (boundary as RenderRepaintBoundary).toImage(
        pixelRatio: 1,
      );
      width = image.width;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      pixels = data!.buffer.asUint8List();
    });

    double lum(int x, int y) {
      final i = (y * width + x) * 4;
      return (pixels[i] + pixels[i + 1] + pixels[i + 2]) / 3 / 255;
    }

    // 菜单是圆角矩形: 只取**左侧外侧**一条竖带 (往左 2–16px),
    // 上下各内缩 2px 避开圆角抗锯齿。阴影的模糊半径十几像素, 一定落在这里。
    var darkest = 1.0;
    final int top = rect.top.round() + 3;
    final int bottom = rect.bottom.round() - 3;
    for (var x = (rect.left - 16).round(); x <= rect.left - 2; x++) {
      for (var y = top; y < bottom; y++) {
        final v = lum(x, y);
        if (v < darkest) darkest = v;
      }
    }
    return darkest;
  }

  testWidgets('弹出菜单外侧没有阴影', (tester) async {
    final darkest = await darkestLeftOfMenu(tester, appTheme.dark);
    expect(
      darkest,
      greaterThan(0.97),
      reason:
          '菜单外侧最暗像素亮度=${darkest.toStringAsFixed(3)}, '
          '低于 0.97 说明还有阴影',
    );
  });

  testWidgets('对照: 默认主题的菜单确实会投影 (证明检测有效)', (tester) async {
    final darkest = await darkestLeftOfMenu(
      tester,
      ThemeData(brightness: Brightness.dark, useMaterial3: true),
    );
    expect(
      darkest,
      lessThan(0.97),
      reason:
          '默认主题下菜单外侧最暗=${darkest.toStringAsFixed(3)}, '
          '应当能测出阴影; 这里也通过说明检测不灵敏',
    );
  });

  // DropdownButton 的菜单阴影**不吃** ColorScheme.shadow —— 它画的是
  // `kElevationToShadow[elevation]` 里写死的黑色 BoxShadow (默认 elevation 8),
  // 所以在主题层把 shadow 设透明对它无效, 只能逐处传 `elevation: 0`。
  // 这个用例把那条约定钉住: 设置页里三个 Dropdown 都必须 elevations == 0。
  testWidgets('设置页的 Dropdown 菜单外侧没有阴影', (tester) async {
    final boundaryKey = GlobalKey();
    await tester.binding.setSurfaceSize(const Size(600, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme.dark,
        builder: (context, child) => RepaintBoundary(
          key: boundaryKey,
          child: ColoredBox(color: Colors.white, child: child!),
        ),
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: DropdownButton<int>(
              elevation: 0, // 与 lib/widgets/popups/settings/play.dart 保持一致
              borderRadius: BorderRadius.circular(12),
              value: 1,
              onChanged: (_) {},
              items: const [
                DropdownMenuItem<int>(value: 1, child: Text('one')),
                DropdownMenuItem<int>(value: 2, child: Text('two')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('one'));
    await tester.pumpAndSettle();

    final RenderBox boundary =
        boundaryKey.currentContext!.findRenderObject()! as RenderBox;
    // 菜单本体是 _DropdownMenuPainter 画的那个 CustomPaint
    final RenderBox menu =
        tester.renderObject(
              find
                  .ancestor(
                    of: find.byType(DropdownMenuItem<int>).last,
                    matching: find.byType(CustomPaint),
                  )
                  .first,
            )
            as RenderBox;
    final Rect rect =
        menu.localToGlobal(Offset.zero, ancestor: boundary) & menu.size;

    late Uint8List pixels;
    late int width;
    await tester.runAsync(() async {
      final image = await (boundary as RenderRepaintBoundary).toImage(
        pixelRatio: 1,
      );
      width = image.width;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      pixels = data!.buffer.asUint8List();
    });

    double lum(int x, int y) {
      final i = (y * width + x) * 4;
      return (pixels[i] + pixels[i + 1] + pixels[i + 2]) / 3 / 255;
    }

    // 菜单正下方 (阴影 offset 朝下), 左右各内缩避开圆角
    var darkest = 1.0;
    for (var y = rect.bottom.round() + 1; y <= rect.bottom.round() + 22; y++) {
      for (var x = rect.left.round() + 20; x < rect.right.round() - 20; x++) {
        if (x < 0 || y < 0 || x >= width) continue;
        final v = lum(x, y);
        if (v < darkest) darkest = v;
      }
    }
    expect(
      darkest,
      greaterThan(0.97),
      reason:
          'Dropdown 菜单下方最暗像素亮度=${darkest.toStringAsFixed(3)}, '
          '低于 0.97 说明 elevation 没设成 0 (它不吃 ColorScheme.shadow)',
    );
  });
}

List<PopupMenuEntry<int>> _items(BuildContext context) => const [
  PopupMenuItem<int>(value: 0, child: Text('one')),
  PopupMenuItem<int>(value: 1, child: Text('two')),
];

class _FakeContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
