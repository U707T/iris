import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/short_video/short_video_view.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:provider/provider.dart';

/// 短视频模式鼠标滚轮行为测试:
/// 指针在界面任意位置 (视频区域 / 底部信息栏 / 进度条 / 侧边按钮) 滚动,
/// 都应切换到上一条 / 下一条; PageView 默认的滚轮翻页应被接管。

MediaPlayer _fakePlayer({
  bool isPlaying = false,
  Duration position = Duration.zero,
  void Function(Duration)? onSeek,
}) =>
    MediaPlayer(
      isInitializing: false,
      isPlaying: isPlaying,
      externalSubtitles: const [],
      position: position,
      duration: const Duration(minutes: 5),
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
      seek: (d) async => onSeek?.call(d),
    );

List<PlayQueueItem> _queue() => [
      for (var i = 0; i < 3; i++)
        PlayQueueItem(
          file: FileItem(name: 'v$i', uri: 'v$i', type: ContentType.video),
          index: i,
        ),
    ];

/// 设置播放队列与当前下标。
/// 测试体内是 fake async 区域, 插件通道调用的 future 不会完成,
/// 因此用 [WidgetTester.runAsync] 在真实异步环境中执行。
Future<void> _setQueue(WidgetTester tester, int index) async {
  await tester.runAsync(() async {
    await usePlayQueueStore().update(playQueue: _queue(), index: index);
  });
}

Future<void> _pumpView(WidgetTester tester) async {
  await tester.pumpWidget(
    StoreScope(
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Provider<MediaPlayer>.value(
            value: _fakePlayer(),
            child: const ShortVideoView(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 在指定位置发送一次鼠标滚轮事件
Future<void> _wheelAt(
  WidgetTester tester,
  Offset position, {
  double dy = 100,
}) async {
  await tester.sendEventToBinding(PointerScrollEvent(
    position: position,
    scrollDelta: Offset(0, dy),
  ));
  await tester.pumpAndSettle();
}

/// 卸载界面树, 保证用例间互不影响
Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

void main() {
  testWidgets('滚轮在视频区域: 切换到下一条', (tester) async {
    await _setQueue(tester, 0);
    await _pumpView(tester);
    expect(usePlayQueueStore().state.currentIndex, 0);

    await _wheelAt(tester, const Offset(400, 300));
    expect(usePlayQueueStore().state.currentIndex, 1);

    await _teardown(tester);
  });

  testWidgets('滚轮在底部信息栏: 切换到下一条', (tester) async {
    await _setQueue(tester, 0);
    await _pumpView(tester);
    expect(usePlayQueueStore().state.currentIndex, 0);

    // 底部信息栏 (标题 / 序号 / 时间) 会吸收命中测试, 滚轮需要由根部兜底
    await _wheelAt(tester, const Offset(400, 520));
    expect(usePlayQueueStore().state.currentIndex, 1);

    await _teardown(tester);
  });

  testWidgets('滚轮在进度条区域: 切换到下一条', (tester) async {
    await _setQueue(tester, 0);
    await _pumpView(tester);
    expect(usePlayQueueStore().state.currentIndex, 0);

    await _wheelAt(tester, const Offset(400, 584));
    expect(usePlayQueueStore().state.currentIndex, 1);

    await _teardown(tester);
  });

  testWidgets('滚轮在右侧按钮区域: 切换到下一条', (tester) async {
    await _setQueue(tester, 0);
    await _pumpView(tester);
    expect(usePlayQueueStore().state.currentIndex, 0);

    final buttonCenter = tester.getCenter(find.byIcon(Icons.play_arrow_rounded));
    await _wheelAt(tester, buttonCenter);
    expect(usePlayQueueStore().state.currentIndex, 1);

    await _teardown(tester);
  });

  testWidgets('向上滚动: 切换到上一条', (tester) async {
    await _setQueue(tester, 1);
    await _pumpView(tester);
    expect(usePlayQueueStore().state.currentIndex, 1);

    await _wheelAt(tester, const Offset(400, 300), dy: -100);
    expect(usePlayQueueStore().state.currentIndex, 0);

    await _teardown(tester);
  });

  testWidgets('横向拖动快进: 从当前播放位置开始 (回归: 不再从头开始)', (tester) async {
    final seeks = <Duration>[];
    var fake = _fakePlayer(
      isPlaying: true,
      position: const Duration(seconds: 30),
      onSeek: seeks.add,
    );
    late StateSetter swap;

    await _setQueue(tester, 0);

    await tester.pumpWidget(
      StoreScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                swap = setState;
                return Provider<MediaPlayer>.value(
                  value: fake,
                  child: const ShortVideoView(),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 模拟"播放持续推进但 ShortVideoView 未重建"的真实场景:
    // 换成 position 更新的播放器实例 (30s → 60s); ShortVideoView 是 const 子组件, 不会随之重建
    swap(() {
      fake = _fakePlayer(
        isPlaying: true,
        position: const Duration(seconds: 60),
        onSeek: seeks.add,
      );
    });
    await tester.pump();

    // 从屏幕中心右滑 90px (灵敏度 3px/s → 约 +30s)
    await tester.drag(find.byType(ShortVideoView), const Offset(90, 0));
    await tester.pumpAndSettle();
    // 等拖动结束后的预览清理定时器
    await tester.pump(const Duration(milliseconds: 400));

    expect(seeks, isNotEmpty);
    // 关键回归点: 拖动从"当前播放位置"(60s)开始, 而不是捕获实例里的过期位置
    expect(seeks.first, const Duration(seconds: 60));
    // 所有 seek 都落在 [当前, 当前+30s] 区间, 不会跳回 30s / 0
    expect(seeks.every((s) => s.inSeconds >= 60 && s.inSeconds <= 90), isTrue);

    await _teardown(tester);
  });

  testWidgets('细粒度滚轮增量: 累积到阈值后切换 (高精度滚轮 / 远程桌面回归)', (tester) async {
    await _setQueue(tester, 0);
    await _pumpView(tester);
    expect(usePlayQueueStore().state.currentIndex, 0);

    // 每次仅 10px (细粒度设备), 累积到 30px 阈值后只切换一次
    for (var i = 0; i < 4; i++) {
      await tester.sendEventToBinding(PointerScrollEvent(
        position: const Offset(400, 300),
        scrollDelta: const Offset(0, 10),
      ));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(usePlayQueueStore().state.currentIndex, 1);

    await _teardown(tester);
  });

  testWidgets('微小滚轮噪声 (1px) 不触发切换', (tester) async {
    await _setQueue(tester, 0);
    await _pumpView(tester);

    for (var i = 0; i < 10; i++) {
      await tester.sendEventToBinding(PointerScrollEvent(
        position: const Offset(400, 300),
        scrollDelta: const Offset(0, 1),
      ));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(usePlayQueueStore().state.currentIndex, 0);

    await _teardown(tester);
  });

  testWidgets('反向滚动重置累积: 先下后上只向上切换一次', (tester) async {
    await _setQueue(tester, 1);
    await _pumpView(tester);

    // 向下 20px 不足阈值; 随后反向 3 × 20px → 应只向「上一条」切换一次
    await tester.sendEventToBinding(PointerScrollEvent(
      position: const Offset(400, 300),
      scrollDelta: const Offset(0, 20),
    ));
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await tester.sendEventToBinding(PointerScrollEvent(
        position: const Offset(400, 300),
        scrollDelta: const Offset(0, -20),
      ));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(usePlayQueueStore().state.currentIndex, 0);

    await _teardown(tester);
  });

  testWidgets('滚轮动作间隔过久: 累积重新计数', (tester) async {
    await _setQueue(tester, 0);
    await _pumpView(tester);

    await tester.sendEventToBinding(PointerScrollEvent(
      position: const Offset(400, 300),
      scrollDelta: const Offset(0, 20),
    ));
    await tester.pumpAndSettle();

    // 超过手势间隔 (400ms) 后重新计数: 若未重置, 20 + 20 就会达到阈值
    await tester.runAsync(() => Future<void>.delayed(
          const Duration(milliseconds: 500),
        ));
    await tester.sendEventToBinding(PointerScrollEvent(
      position: const Offset(400, 300),
      scrollDelta: const Offset(0, 20),
    ));
    await tester.pump();
    expect(usePlayQueueStore().state.currentIndex, 0);

    // 新一轮累积 20 + 20 → 达到阈值, 切换
    await tester.sendEventToBinding(PointerScrollEvent(
      position: const Offset(400, 300),
      scrollDelta: const Offset(0, 20),
    ));
    await tester.pumpAndSettle();
    expect(usePlayQueueStore().state.currentIndex, 1);

    await _teardown(tester);
  });
}
