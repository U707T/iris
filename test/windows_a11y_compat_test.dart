import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:iris/utils/windows_a11y_compat.dart';

/// Windows 无障碍兼容开关测试 (flutter/flutter#175041 的临时规避方案):
/// 默认开启 (已植入, 无需任何参数); 仅 Windows 生效;
/// 可用环境变量或命令行参数显式退出 (恢复无障碍)。
void main() {
  group('shouldDisableWindowsA11y', () {
    test('非 Windows 平台: 即使设置了退出开关也返回 false', () {
      expect(
        shouldDisableWindowsA11y(
          isWindows: false,
          environment: const {kEnableWindowsA11yEnvironment: '1'},
          arguments: const [kEnableWindowsA11yArgument],
        ),
        isFalse,
      );
    });

    test('Windows + 无任何开关: 默认开启 (兼容已植入)', () {
      expect(
        shouldDisableWindowsA11y(
          isWindows: true,
          environment: const {},
          arguments: const [],
        ),
        isTrue,
      );
    });

    test('Windows + 环境变量退出: 恢复无障碍', () {
      for (final value in ['1', 'true', 'TRUE', 'Yes', 'on', ' 1 ']) {
        expect(
          shouldDisableWindowsA11y(
            isWindows: true,
            environment: {kEnableWindowsA11yEnvironment: value},
            arguments: const [],
          ),
          isFalse,
          reason: 'value=$value',
        );
      }
    });

    test('Windows + 退出环境变量为其他值: 不视为退出', () {
      for (final value in ['0', 'false', 'no', 'off', '']) {
        expect(
          shouldDisableWindowsA11y(
            isWindows: true,
            environment: {kEnableWindowsA11yEnvironment: value},
            arguments: const [],
          ),
          isTrue,
          reason: 'value=$value',
        );
      }
    });

    test('Windows + 命令行参数退出: 恢复无障碍 (与文件路径参数共存)', () {
      expect(
        shouldDisableWindowsA11y(
          isWindows: true,
          environment: const {},
          arguments: const [r'D:\movie.mp4', kEnableWindowsA11yArgument],
        ),
        isFalse,
      );
    });

    test('Windows + 旧 disable 开关: 保持开启 (向后兼容, 冗余无害)', () {
      expect(
        shouldDisableWindowsA11y(
          isWindows: true,
          environment: const {kDisableWindowsA11yEnvironment: '1'},
          arguments: const [kDisableWindowsA11yArgument],
        ),
        isTrue,
      );
    });

    test('Windows + 退出开关与旧 disable 开关同时存在: 退出优先', () {
      expect(
        shouldDisableWindowsA11y(
          isWindows: true,
          environment: const {
            kEnableWindowsA11yEnvironment: '1',
            kDisableWindowsA11yEnvironment: '1',
          },
          arguments: const [],
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
