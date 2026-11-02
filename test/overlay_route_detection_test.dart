import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/widgets/popup.dart';

/// 「有没有弹层压在播放器上」是控制栏自动隐藏的一个输入。
///
/// 旧实现靠每个按钮自己把 `isHovering` 置 true（只有一部分入口记得），
/// 新实现直接读路由栈：`ModalRoute.of(context)?.isCurrent == false`。
/// 这里验证这个判定确实会被项目的几种弹层翻转 —— 包括本项目自制的
/// `Popup`（透明 barrier）、`PopupMenuButton`（更多 / 倍速菜单）和对话框。
void main() {
  testWidgets('项目自制的 Popup: 打开期间 isCurrent=false, 关闭后恢复', (tester) async {
    final states = <bool>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              // 与 Player.build 里的读法完全一致
              final isCurrent = ModalRoute.of(context)?.isCurrent ?? true;
              states.add(isCurrent);
              return Center(
                child: ElevatedButton(
                  onPressed: () => showPopup(
                    context: context,
                    child: const SizedBox(width: 100, height: 100),
                    direction: PopupDirection.right,
                  ),
                  child: const Text('open'),
                ),
              );
            },
          ),
        ),
      ),
    );
    expect(states.last, isTrue);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(states.last, isFalse, reason: '弹层打开期间, 播放器不再是当前路由');

    // 点空白处关掉（Popup 的 barrier 会 pop）
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(states.last, isTrue, reason: '弹层关闭后恢复, 计时才能继续');
  });

  testWidgets('PopupMenuButton（更多 / 倍速菜单）同样会翻转 isCurrent', (tester) async {
    final states = <bool>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              states.add(ModalRoute.of(context)?.isCurrent ?? true);
              return Center(
                child: PopupMenuButton<int>(
                  itemBuilder: (_) => const [
                    PopupMenuItem<int>(value: 1, child: Text('item')),
                  ],
                  child: const Text('menu'),
                ),
              );
            },
          ),
        ),
      ),
    );
    expect(states.last, isTrue);

    await tester.tap(find.text('menu'));
    await tester.pumpAndSettle();
    expect(states.last, isFalse, reason: '菜单是路由, 打开时控制栏不该被收走');

    await tester.tap(find.text('item'));
    await tester.pumpAndSettle();
    expect(states.last, isTrue);
  });

  testWidgets('对话框同样被算作弹层', (tester) async {
    final states = <bool>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              states.add(ModalRoute.of(context)?.isCurrent ?? true);
              return Center(
                child: ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const AlertDialog(title: Text('dlg')),
                  ),
                  child: const Text('dialog'),
                ),
              );
            },
          ),
        ),
      ),
    );
    expect(states.last, isTrue);

    await tester.tap(find.text('dialog'));
    await tester.pumpAndSettle();
    expect(states.last, isFalse);

    await tester.tapAt(const Offset(10, 10)); // barrier dismiss
    await tester.pumpAndSettle();
    expect(states.last, isTrue);
  });
}
