import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
  setUpAll(() async {
    const dir = '/opt/flutter/bin/cache/artifacts/material_fonts';
    final loader = FontLoader('Roboto');
    for (final f in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf']) {
      final bytes = File('$dir/$f').readAsBytesSync();
      loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  });

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
        tester.renderObject(find.byType(PopupMenuItem<int>).first)
            as RenderBox;
    final Rect rect =
        item.localToGlobal(Offset.zero, ancestor: boundary) & item.size;

    late Uint8List pixels;
    late int width;
    await tester.runAsync(() async {
      final image =
          await (boundary as RenderRepaintBoundary).toImage(pixelRatio: 1);
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
      reason: '菜单外侧最暗像素亮度=${darkest.toStringAsFixed(3)}, '
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
      reason: '默认主题下菜单外侧最暗=${darkest.toStringAsFixed(3)}, '
          '应当能测出阴影; 这里也通过说明检测不灵敏',
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
