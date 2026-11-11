import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/models/store/play_queue_state.dart';
import 'package:iris/pages/player/control_bar/control_bar.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/utils/platform.dart';
import 'package:provider/provider.dart';

MediaPlayer _dummyPlayer() => MediaPlayer(
      isInitializing: false,
      isPlaying: false,
      position: Duration.zero,
      duration: Duration.zero,
      buffer: Duration.zero,
      width: 0,
      height: 0,
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

Future<void> _pumpControlBar(
  WidgetTester tester,
  double width, {
  int items = 2,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  usePlayQueueStore().set(
    PlayQueueState(
      playQueue: [
        for (var i = 0; i < items; i++)
          PlayQueueItem(
            file: FileItem(
              name: '${i + 1}.mp4',
              uri: '${i + 1}.mp4',
              type: ContentType.video,
            ),
            index: i,
          ),
      ],
      currentIndex: 0,
    ),
  );

  await tester.pumpWidget(
    StoreScope(
      child: Provider<MediaPlayer>.value(
        value: _dummyPlayer(),
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: MediaQuery(
                // ControlBar 用 MediaQuery 的宽度选布局, 必须和实际约束一致,
                // 否则测到的是"桌面布局被塞进 360 宽"的假溢出。
                data: MediaQueryData(size: Size(width, 400)),
                child: SizedBox(
                  width: width,
                  height: 220,
                  child: ControlBar(
                    showControl: () {},
                    showControlForHover: (callback) async => await callback,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() {
    // 控制栏里的「横竖屏」按钮 (以及更多菜单里的移动端条目) 只在移动端出现,
    // 但测试跑在 Linux 宿主上 —— 不覆盖平台判定, 测到的永远是桌面布局。
    debugIsDesktopOverride = false;
  });
  tearDown(() => debugIsDesktopOverride = null);

  // 320 是窄机下限; 360 / 411 是主流手机; 448 / 512 卡住「音轨 / 存储」收起
  // 的临界点; 640 / 900 是平板与窄窗口; 1024 起是桌面单行。
  // 任何一档溢出都会让测试失败。
  for (final width in <double>[
    320,
    360,
    411,
    448,
    512,
    640,
    900,
    1024,
    1200,
    1280,
  ]) {
    testWidgets('控制栏在 ${width.toInt()} 宽不溢出', (tester) async {
      await _pumpControlBar(tester, width);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('停止 / 缩放按钮已从控制栏移除', (tester) async {
    await _pumpControlBar(tester, 360);

    expect(find.byIcon(Icons.stop_rounded), findsNothing);
    expect(find.byIcon(Icons.zoom_in_rounded), findsNothing);
  });

  testWidgets('360 宽的第二排: 画面 → 音量 → 队列 → 短视频 → 刷新 → 横竖屏 → 更多',
      (tester) async {
    await _pumpControlBar(tester, 360);

    // 按从左到右的预期顺序; 每一项都必须存在且 x 递增
    final List<Finder> row = [
      find.byIcon(Icons.fit_screen_rounded),
      find.byIcon(Icons.volume_up_rounded),
      find.byIcon(Icons.playlist_play_rounded),
      find.byIcon(Icons.swipe_vertical_rounded),
      find.byIcon(Icons.refresh_rounded),
      find.byIcon(Icons.screen_rotation_rounded),
      find.byIcon(Icons.more_vert_rounded),
    ];

    final List<double> xs = [
      for (final finder in row) tester.getCenter(finder).dx,
    ];

    expect(xs, orderedEquals([...xs]..sort()), reason: '第二排按钮顺序: $xs');
    // 横竖屏是倒数第二个 (右边只剩「更多」), 刷新紧挨着它
    expect(xs[xs.length - 2], lessThan(xs.last));
    // 第一排只有五个: 随机 / 上一个 / 播放 / 下一个 / 循环
    expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
    expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);
  });

  testWidgets('第一排的播放键在正中间 (上 / 下一个隐藏时也一样)', (tester) async {
    // "停止"删掉之后第一排是 随机 | 上 | 播 | 下 | 循环; 队列只有一条时
    // 上 / 下一个会退化成 SizedBox.shrink() —— spaceEvenly 仍按 5 个槽位分,
    // 所以中间那一格还落在正中。这条断言把"居中"钉死, 免得以后往第一排
    // 加按钮时悄悄把播放键挤偏。
    for (final int items in <int>[1, 2, 4]) {
      await _pumpControlBar(tester, 360, items: items);

      final double center = tester.getRect(find.byType(ControlBar)).center.dx;
      final double play =
          tester.getCenter(find.byIcon(Icons.play_arrow_rounded)).dx;
      expect(play, closeTo(center, 0.5), reason: '队列 $items 条: play=$play');

      // 两侧的模式键对称, 进一步确认隐藏按钮没有把整排推偏
      final double shuffle =
          tester.getCenter(find.byIcon(Icons.shuffle_rounded)).dx;
      final double repeat =
          tester.getCenter(find.byIcon(Icons.repeat_rounded)).dx;
      expect(shuffle + repeat, closeTo(center * 2, 1), reason: '队列 $items 条');
    }
  });

  testWidgets('第二排的横竖屏按钮一键在横 / 纵之间切换', (tester) async {
    await _pumpControlBar(tester, 360);

    final Finder toggle = find.byIcon(Icons.screen_rotation_rounded);
    // 跟随设备时, 第一下默认切横向 (手机上竖着拿是常态)
    expect(find.byTooltip('切换到横屏'), findsOneWidget);

    await tester.tap(toggle);
    await tester.pump();
    expect(useAppStore().state.orientation, ScreenOrientation.landscape);

    // 提示跟着状态走: 重新构建一棵树再断言 (flutter_zustand 的 StoreScope 每次
    // dispose 都会关掉 StoreLocator 的 changes 流, 单测里连 pump 多棵树之后
    // `select` 的变更通知就送不到了 —— 只影响测试, 不影响 App 里只有一个根)。
    await _pumpControlBar(tester, 360);
    expect(find.byTooltip('切换到竖屏'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.screen_rotation_rounded));
    await tester.pump();
    expect(useAppStore().state.orientation, ScreenOrientation.portrait);
  });
}
