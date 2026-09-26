import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:iris/utils/windows_a11y_compat.dart';

/// Windows 无障碍兼容开关测试 (flutter/flutter#175041 的临时规避方案):
/// 默认关闭; 仅 Windows 生效; 可用环境变量或命令行参数开启。
void main() {
  group('shouldDisableWindowsA11y', () {
    test('非 Windows 平台: 即使开关都设置了也返回 false', () {
      expect(
        shouldDisableWindowsA11y(
          isWindows: false,
          environment: const {kDisableWindowsA11yEnvironment: '1'},
          arguments: const [kDisableWindowsA11yArgument],
        ),
        isFalse,
      );
    });

    test('Windows + 环境变量=1: 开启', () {
      expect(
        shouldDisableWindowsA11y(
          isWindows: true,
          environment: const {kDisableWindowsA11yEnvironment: '1'},
          arguments: const [],
        ),
        isTrue,
      );
    });

    test('Windows + 环境变量容忍大小写与空白 (true/TRUE/Yes/on/ 1 )', () {
      for (final value in ['true', 'TRUE', 'Yes', 'on', ' 1 ']) {
        expect(
          shouldDisableWindowsA11y(
            isWindows: true,
            environment: {kDisableWindowsA11yEnvironment: value},
            arguments: const [],
          ),
          isTrue,
          reason: 'value=$value',
        );
      }
    });

    test('Windows + 环境变量为其他值: 不开启', () {
      for (final value in ['0', 'false', 'no', 'off', '']) {
        expect(
          shouldDisableWindowsA11y(
            isWindows: true,
            environment: {kDisableWindowsA11yEnvironment: value},
            arguments: const [],
          ),
          isFalse,
          reason: 'value=$value',
        );
      }
    });

    test('Windows + 命令行参数: 开启 (与文件路径参数共存)', () {
      expect(
        shouldDisableWindowsA11y(
          isWindows: true,
          environment: const {},
          arguments: const [r'D:\movie.mp4', kDisableWindowsA11yArgument],
        ),
        isTrue,
      );
    });

    test('Windows + 未设置 / 无关参数: 不开启', () {
      expect(
        shouldDisableWindowsA11y(
          isWindows: true,
          environment: const {},
          arguments: const [],
        ),
        isFalse,
      );
      expect(
        shouldDisableWindowsA11y(
          isWindows: true,
          environment: const {},
          arguments: const [r'D:\movie.mp4'],
        ),
        isFalse,
      );
    });
  });

  group('maybeExcludeSemantics', () {
    testWidgets('开关开启: 包一层 ExcludeSemantics (语义树被整体排除)', (tester) async {
      await tester.pumpWidget(
        maybeExcludeSemantics(
          disabled: true,
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: Text('x'),
          ),
        ),
      );
      expect(find.byType(ExcludeSemantics), findsOneWidget);
      expect(find.text('x'), findsOneWidget);
    });

    testWidgets('开关关闭: 原样返回 (不引入额外节点)', (tester) async {
      await tester.pumpWidget(
        maybeExcludeSemantics(
          disabled: false,
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: Text('x'),
          ),
        ),
      );
      expect(find.byType(ExcludeSemantics), findsNothing);
      expect(find.text('x'), findsOneWidget);
    });
  });
}