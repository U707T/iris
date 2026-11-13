import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/globals.dart' as globals;
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/models/store/play_queue_state.dart';
import 'package:iris/pages/player/control_bar/control_bar.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/widgets/popups/settings/play.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

MediaPlayer _dummyPlayer() => MediaPlayer(
      isInitializing: false,
      isPlaying: false,
      position: Duration.zero,
      duration: Duration.zero,
      buffer: Duration.zero,
      width: 1920,
      height: 1080,
      saveProgress: () async {},
      play: () async {},
      pause: () async {},
      backward: (_) async {},
      forward: (_) async {},
      stepBackward: () async {},
      stepForward: () async {},
      seek: (_) async {},
      screenshot: () async => null,
      getStats: () => const {},
    );

Widget _app(Widget child) => StoreScope(
      child: Provider<MediaPlayer>.value(
        value: _dummyPlayer(),
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        ),
      ),
    );

/// 「设置 → 播放 → 画中画」这个开关, 以及它控制的「更多 → 进入画中画」入口。
///
/// 两处都读同一份能力探测结果 (globals.pictureInPictureSupported) 和同一个
/// AppState 字段, 所以一起验: 开关本身要能点、能落状态; 能力不支持时整项
/// 不出现 —— 留一个点了没反应的开关比不给入口更糟。
void main() {
  late Directory supportDir;

  setUpAll(() async {
    // AppStore / PlayQueueStore 的持久化目录在测试环境没有插件实现,
    // 不挡住会变成"测试结束后才到达的异常"。给它一个临时目录即可。
    supportDir = await Directory.systemTemp.createTemp('iris_pip_settings');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => supportDir.path,
    );
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (supportDir.existsSync()) await supportDir.delete(recursive: true);
  });

  tearDown(() => globals.pictureInPictureSupported = false);

  testWidgets('不支持画中画时设置项不出现', (tester) async {
    _resetStores();
    globals.pictureInPictureSupported = false;

    await tester.pumpWidget(_app(const Play()));
    await tester.pump();

    expect(find.text('画中画'), findsNothing);
  });

  testWidgets('开关默认关闭, 点一下打开并写进 AppState', (tester) async {
    _resetStores();
    globals.pictureInPictureSupported = true;

    await tester.pumpWidget(_app(const Play()));
    await tester.pump();

    expect(find.text('画中画'), findsOneWidget);

    final checkbox = find.descendant(
      of: find.widgetWithText(ListTile, '画中画'),
      matching: find.byType(Checkbox),
    );
    expect(tester.widget<Checkbox>(checkbox).value, isFalse,
        reason: '默认不开启画中画');

    // 点整行, 而不是标题那几个字 —— 用户点的是一行。
    await tester.tap(find.widgetWithText(ListTile, '画中画'));
    await tester.pump();

    expect(useAppStore().state.pictureInPicture, isTrue);
  });

  testWidgets('状态为开时复选框是勾上的', (tester) async {
    _resetStores(pictureInPicture: true);
    globals.pictureInPictureSupported = true;

    await tester.pumpWidget(_app(const Play()));
    await tester.pump();

    final checkbox = find.descendant(
      of: find.widgetWithText(ListTile, '画中画'),
      matching: find.byType(Checkbox),
    );
    expect(tester.widget<Checkbox>(checkbox).value, isTrue);
  });

  testWidgets('开关关着时「更多」菜单里没有入口', (tester) async {
    _resetStores();
    globals.pictureInPictureSupported = true;
    await _pumpControlBar(tester);

    await tester.tap(find.byKey(globals.moreMenuKey));
    await tester.pumpAndSettle();

    expect(find.text('进入画中画'), findsNothing);
  });

  testWidgets('开关打开后「更多」菜单里能进入画中画', (tester) async {
    _resetStores(pictureInPicture: true);
    globals.pictureInPictureSupported = true;
    await _pumpControlBar(tester);

    await tester.tap(find.byKey(globals.moreMenuKey));
    await tester.pumpAndSettle();

    expect(find.text('进入画中画'), findsOneWidget);
  });
}

/// 在**测试体内**初始化 store。
///
/// 放到 `setUp` 里会踩到 flutter_test 的假异步区域问题: store 在测试体外
/// （或上一个用例的 zone 里）创建之后, 它之后的变更不会再通知到当前用例的
/// widget, 断言会看到一份不刷新的界面。这里只读"当前状态", 每个用例自己
/// 把状态摆好再 pump。
void _resetStores({bool pictureInPicture = false}) {
  useAppStore().set(AppState(pictureInPicture: pictureInPicture));
  usePlayQueueStore().set(
    PlayQueueState(
      playQueue: [
        PlayQueueItem(
          file: FileItem(
            name: 'a.mp4',
            uri: 'a.mp4',
            type: ContentType.video,
          ),
          index: 0,
        ),
      ],
      currentIndex: 0,
    ),
  );
}

Future<void> _pumpControlBar(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(360, 400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    _app(
      const Center(
        child: SizedBox(
          width: 360,
          height: 220,
          child: ControlBar(
            showControl: _noop,
            showControlForHover: _noopHover,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void _noop() {}

Future<void> _noopHover(Future<void> callback) => callback;
