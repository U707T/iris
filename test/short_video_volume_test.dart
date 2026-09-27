import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/short_video/short_video_view.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/widgets/speed_boost_effect.dart';
import 'package:provider/provider.dart';

/// 短视频模式音量按钮测试:
/// - 长按音量按钮后上下滑动调节音量 (仅在按钮上生效)
/// - 滑动过程不触发翻页 (队列下标不变)
/// - 画面区域长按仍是倍速, 不会改音量

MediaPlayer _fakePlayer() => MediaPlayer(
      isInitializing: false,
      isPlaying: true,
      externalSubtitles: const [],
      position: Duration.zero,
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
      seek: (_) async {},
    );

List<PlayQueueItem> _queue() => [
      for (var i = 0; i < 3; i++)
        PlayQueueItem(
          file: FileItem(name: 'v$i', uri: 'v$i', type: ContentType.video),
          index: i,
        ),
    ];

Future<void> _setQueue(WidgetTester tester, int index) async {
  await tester.runAsync(() async {
    await usePlayQueueStore().update(playQueue: _queue(), index: index);
  });
}

Future<void> _setVolume(WidgetTester tester, int volume) async {
  await tester.runAsync(() async {
    await useAppStore().updateVolume(volume, persist: false);
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

void main() {
  testWidgets('长按音量按钮上滑: 提高音量且不翻页', (tester) async {
    await _setQueue(tester, 0);
    await _setVolume(tester, 20);
    await _pumpView(tester);

    // 20% -> volume_down 图标 (按钮上唯一)
    final button = find.byIcon(Icons.volume_down_rounded);
    expect(button, findsOneWidget);

    final center = tester.getCenter(button);
    final gesture = await tester.startGesture(center);
    // 按住不动 600ms -> 触发长按
    await tester.pump(const Duration(milliseconds: 600));
    // 上滑 52px = 提高 20%
    await gesture.moveBy(const Offset(0, -52));
    await tester.pump();

    // 调节指示器出现 (松手后保留一小段时间)
    expect(find.text('40%'), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();

    expect(useAppStore().state.volume, 40);
    // 滑动只调音量, 不翻页
    expect(usePlayQueueStore().state.currentIndex, 0);

    // 指示器随后消失 (预览值保留 320ms)
    expect(find.text('40%'), findsNothing);

    await _setVolume(tester, 20);
    await _setQueue(tester, 0);
  });

  testWidgets('长按音量按钮下滑: 降低音量 (下限 0)', (tester) async {
    await _setQueue(tester, 0);
    await _setVolume(tester, 20);
    await _pumpView(tester);

    final button = find.byIcon(Icons.volume_down_rounded);
    final center = tester.getCenter(button);
    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 600));
    // 下滑 130px = 降低 50% -> 夹到 0
    await gesture.moveBy(const Offset(0, 130));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(useAppStore().state.volume, 0);
    expect(usePlayQueueStore().state.currentIndex, 0);

    await _setVolume(tester, 20);
    await _setQueue(tester, 0);
  });

  testWidgets('画面区域长按仍为倍速, 不影响音量', (tester) async {
    await _setQueue(tester, 0);
    await _setVolume(tester, 40);
    await _pumpView(tester);

    final size = tester.getSize(find.byType(ShortVideoView));
    final gesture = await tester.startGesture(Offset(size.width / 2, size.height / 2));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, -52));
    await tester.pump();

    // 倍速生效 (长按加速), 音量不变
    expect(useAppStore().state.rate, useAppStore().state.longPressSpeed);
    expect(useAppStore().state.volume, 40);

    // 长按加速光效: 左右各一道光带 (不再用画面中央的倍速文字)
    expect(find.byKey(SpeedBoostEffect.leftGlowKey), findsOneWidget);
    expect(find.byKey(SpeedBoostEffect.rightGlowKey), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byKey(SpeedBoostEffect.leftGlowKey), findsNothing);
    expect(find.byKey(SpeedBoostEffect.rightGlowKey), findsNothing);

    await tester.runAsync(() async {
      await useAppStore().updateRate(1.0, persist: false);
    });
    await _setVolume(tester, 20);
    await _setQueue(tester, 0);
  });

  testWidgets('长按识别 0.1s: 按住 150ms 后滑动即可调节音量', (tester) async {
    await _setQueue(tester, 0);
    await _setVolume(tester, 20);
    await _pumpView(tester);

    final center = tester.getCenter(find.byIcon(Icons.volume_down_rounded));
    final gesture = await tester.startGesture(center);
    // 只按住 150ms (旧实现要 500ms 才识别长按, 那时滑动既不改音量也不显示指示器)
    await tester.pump(const Duration(milliseconds: 150));
    // 上滑 26px = +10%
    await gesture.moveBy(const Offset(0, -26));
    await tester.pump();

    expect(find.text('30%'), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();

    expect(useAppStore().state.volume, 30);
    expect(usePlayQueueStore().state.currentIndex, 0);

    await _setVolume(tester, 20);
    await _setQueue(tester, 0);
  });

  testWidgets('按住未滑动松手 = 点击 (静音 / 取消静音)', (tester) async {
    await _setQueue(tester, 0);
    await _setVolume(tester, 30);
    await tester.runAsync(() async {
      await useAppStore().updateMute(false);
    });
    await _pumpView(tester);

    final center = tester.getCenter(find.byIcon(Icons.volume_down_rounded));

    // 按住 150ms 没滑动: 长按已接管指针, 松手仍按点击处理 → 静音
    var gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 150));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(useAppStore().state.isMuted, isTrue);
    expect(useAppStore().state.volume, 30);
    expect(find.text('30%'), findsNothing);

    // 再次按住不滑动松手 → 取消静音
    gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 150));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(useAppStore().state.isMuted, isFalse);

    await tester.runAsync(() async {
      await useAppStore().updateMute(false);
    });
    await _setVolume(tester, 20);
    await _setQueue(tester, 0);
  });

  testWidgets('音量按钮在暂停按钮上方, 位于屏幕右下区域', (tester) async {
    await _setQueue(tester, 0);
    await _setVolume(tester, 20);
    await tester.runAsync(() async {
      await useAppStore().updateMute(false);
    });
    await _pumpView(tester);

    final volume = tester.getCenter(find.byIcon(Icons.volume_down_rounded));
    final playPause = tester.getCenter(find.byIcon(Icons.pause_rounded));
    final screenshot = tester.getCenter(find.byIcon(Icons.photo_camera_rounded));

    // 音量 → 暂停 → 截图, 自上而下
    expect(volume.dy, lessThan(playPause.dy));
    expect(playPause.dy, lessThan(screenshot.dy));

    final size = tester.getSize(find.byType(ShortVideoView));
    expect(volume.dx, greaterThan(size.width * 0.8));
    expect(volume.dy, greaterThan(size.height * 0.5));
    expect(volume.dy, lessThan(playPause.dy));
  });
}
