import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/progress.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/pages/player/empty_player.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/theme.dart';
import 'package:iris/utils/playback_progress.dart';
import 'package:iris/widgets/media_row.dart';
import 'package:iris/widgets/panel.dart';
import 'package:iris/widgets/popups/settings/about.dart';
import 'package:iris/widgets/popups/settings/general.dart';
import 'package:iris/widgets/popups/settings/settings.dart';
import 'package:material_ui/material_ui.dart';

/// 这一版 UI 的三条硬规则：
/// 1. 设置项只有一行 —— 没有副标题，当前值在右侧；
/// 2. 开关就是开关（Switch），不是复选框；
/// 3. 关于页没有标语。
void main() {
  late Directory supportDir;

  setUpAll(() async {
    supportDir = await Directory.systemTemp.createTemp('iris_ui_clean');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => supportDir.path,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/package_info'),
          (call) async => <String, dynamic>{
            'appName': 'IRIS',
            'packageName': 'iris',
            'version': '2.7.0',
            'buildNumber': '46',
          },
        );
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/package_info'),
          null,
        );
    if (supportDir.existsSync()) await supportDir.delete(recursive: true);
  });

  setUp(() {
    useAppStore().set(AppState(language: 'zh', themeMode: ThemeMode.dark));
  });

  testWidgets('设置项没有副标题，开关用 Switch', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(const Settings()));
    await tester.pumpAndSettle();

    final tiles = tester.widgetList<ListTile>(find.byType(ListTile));
    expect(tiles, isNotEmpty);
    for (final tile in tiles) {
      expect(tile.subtitle, isNull, reason: '设置项不该再挂一行解释文字');
    }
    expect(find.byType(Switch), findsWidgets);
    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets('语言行打开选择器，选中即生效并关闭', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(const General()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('语言'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(useAppStore().state.language, 'en');
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('关于页没有标语，只有名字和版本', (tester) async {
    await tester.binding.setSurfaceSize(const Size(520, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(const About()));
    await tester.pumpAndSettle();

    expect(find.text('轻量级视频播放器'), findsNothing);
    expect(find.text('IRIS'), findsOneWidget);
    expect(find.text('2.7.0'), findsOneWidget);

    final tiles = tester.widgetList<ListTile>(find.byType(ListTile));
    expect(tiles, isNotEmpty);
    for (final tile in tiles) {
      expect(tile.subtitle, isNull);
    }
  });

  test('进度标签: 0 时长不产生 NaN, 末尾 5 秒算 100%', () {
    expect(
      playbackProgressLabel(
        _progress(
          position: const Duration(minutes: 1),
          duration: Duration.zero,
        ),
      ),
      isNull,
    );
    expect(
      playbackProgressLabel(
        _progress(
          position: const Duration(minutes: 59, seconds: 58),
          duration: const Duration(minutes: 60),
        ),
      ),
      '100%',
    );
    expect(
      playbackProgressLabel(
        _progress(
          position: const Duration(minutes: 21),
          duration: const Duration(minutes: 50),
        ),
      ),
      '42%',
    );
  });

  testWidgets('空状态给的是入口，不再摆一条空控制栏', (tester) async {
    await tester.pumpWidget(_app(const EmptyPlayer()));
    await tester.pumpAndSettle();

    expect(find.text('打开文件'), findsOneWidget);
    expect(find.text('打开链接'), findsOneWidget);
    expect(find.text('存储'), findsOneWidget);
    expect(find.text('历史'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });

  testWidgets('媒体行把进度画成文字，不是胶囊', (tester) async {
    await tester.pumpWidget(
      _app(
        const SizedBox(
          width: 420,
          height: 300,
          child: PanelSurface(
            child: MediaRow(
              icon: Icons.movie_rounded,
              title: 'a.mkv',
              meta: '1.0 GB',
              progress: '42%',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('42%'), findsOneWidget);
    expect(find.byType(Chip), findsNothing);
  });
}

Progress _progress({required Duration position, required Duration duration}) =>
    Progress(
      dateTime: DateTime(2026, 11, 12),
      position: position,
      duration: duration,
      file: const FileItem(
        name: 'a.mkv',
        uri: 'a.mkv',
        type: ContentType.video,
      ),
    );

Widget _app(Widget child) {
  final theme = getTheme(
    context: _FakeContext(),
    lightDynamic: null,
    darkDynamic: null,
  );

  return StoreScope(
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.dark,
      locale: const Locale('zh'),
      localizationsDelegates: [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 460,
            height: 620,
            child: PanelSurface(child: child),
          ),
        ),
      ),
    ),
  );
}

class _FakeContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
