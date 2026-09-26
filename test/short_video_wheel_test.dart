import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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

MediaPlayer _fakePlayer() => MediaPlayer(
      isInitializing: false,
      isPlaying: false,
      externalSubtitles: const [],
      position: Duration.zero,
      duration: const Duration(minutes: 1),
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
        localizationsDelegates: AppLocalizations.localizationsDelegates,
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
}
