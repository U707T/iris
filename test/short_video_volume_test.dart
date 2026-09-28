import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
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
/// - 长按音量按钮后上下滑动调节**设备音量**(绝对音量, 走 FlutterVolumeController,
///   与主界面上下拖动一致), 仅在按钮上生效
/// - 滑动过程不触发翻页 (队列下标不变), 也不会改应用内的音量设置
/// - 画面区域长按仍是倍速, 不会改音量
/// - 点击 = 静音 / 取消静音 (只静音本应用)

/// 记录设备音量调用 (setVolume 的值, 0.0~1.0)
final List<double> deviceVolumeSets = [];
/// 记录设备音量 + 系统音量条开关的调用
final List<String> deviceVolumeCalls = [];

/// 假设备音量 (0.5 = 50%), 并把插件通道换成可断言的假实现
void _mockVolumeController({double volume = 0.5}) {
  deviceVolumeSets.clear();
  deviceVolumeCalls.clear();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(FlutterVolumeController.methodChannel,
          (call) async {
    deviceVolumeCalls.add(call.method);
    switch (call.method) {
      case 'getVolume': // 插件读回来的是字符串
        return '$volume';
      case 'setVolume':
        deviceVolumeSets.add((call.arguments as Map)['volume'] as double);
        return null;
      default:
        return null;
    }
  });
}

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
  setUp(() => _mockVolumeController());
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(FlutterVolumeController.methodChannel, null);
  });

  testWidgets('长按音量按钮上滑: 提高设备音量且不翻页', (tester) async {
    await _setQueue(tester, 0);
    await _setVolume(tester, 20);
    await _pumpView(tester);

    // 20% -> volume_down 图标 (按钮上唯一)
    final button = find.byIcon(Icons.volume_down_rounded);
    expect(button, findsOneWidget);

    final center = tester.getCenter(button);
    final gesture = await tester.startGesture(center);
    // 按住 150ms -> 长按 (100ms) 识别, 并读出设备音量 (mock: 50%)
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(deviceVolumeCalls, contains('getVolume'));
    // 长按一识别就显示当前设备音量
    expect(find.text('50%'), findsOneWidget);

    // 上滑 20px = +10% (2px = 1%)
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();

    expect(find.text('60%'), findsOneWidget);
    expect(deviceVolumeSets.last, closeTo(0.6, 0.001));

    await gesture.up();
    await tester.pumpAndSettle();

    // 设备音量由系统记住: 松开后没有兜底写入, 也没有翻页
    expect(deviceVolumeSets.last, closeTo(0.6, 0.001));
    expect(usePlayQueueStore().state.currentIndex, 0);
    // 应用内的音量设置不受影响 (改的是设备音量)
    expect(useAppStore().state.volume, 20);

    // 指示器随后消失 (预览值保留 320ms)
    expect(find.text('60%'), findsNothing);

    await _setVolume(tester, 20);
    await _setQueue(tester, 0);
  });

  testWidgets('长按音量按钮下滑: 降低设备音量 (下限 0)', (tester) async {
    await _setQueue(tester, 0);
    await _setVolume(tester, 20);
    await _pumpView(tester);

    final center = tester.getCenter(find.byIcon(Icons.volume_down_rounded));
    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    // 下滑 130px = -65% (50% 起) -> 夹到 0
    await gesture.moveBy(const Offset(0, 130));
    await tester.pump();

    expect(find.text('0%'), findsOneWidget);
    expect(deviceVolumeSets.last, closeTo(0.0, 0.001));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(deviceVolumeSets.last, closeTo(0.0, 0.001));
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

    // 倍速生效 (长按加速), 音量不变 (设备音量也没被碰过)
    expect(useAppStore().state.rate, useAppStore().state.longPressSpeed);
    expect(useAppStore().state.volume, 40);
    expect(deviceVolumeSets, isEmpty);

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
    // 上滑 20px = +10% (设备音量 50% -> 60%)
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();

    expect(find.text('60%'), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();

    expect(deviceVolumeSets.last, closeTo(0.6, 0.001));
    expect(usePlayQueueStore().state.currentIndex, 0);

    await _setVolume(tester, 20);
    await _setQueue(tester, 0);
  });

  testWidgets('按住未滑动松手 = 点击 (只静音本应用)', (tester) async {
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
    // 没滑动就不该动设备音量
    expect(deviceVolumeSets, isEmpty);

    // 再次按住不滑动松手 → 取消静音
    gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 150));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(useAppStore().state.isMuted, isFalse);
    expect(deviceVolumeSets, isEmpty);

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
