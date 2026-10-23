import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/gesture/seek_hub.dart';
import 'package:iris/pages/player/gesture/seek_hud.dart';
import 'package:iris/pages/player/short_video/short_video_view.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:provider/provider.dart';

/// 短视频模式的快进 / 快退（与主窗口统一后）：
/// - 双击左 / 右 1/3 = 快退 / 快进（步长取设置），画面中央出现 `±Ns` 提示；
/// - 双击中间 1/3 = 播放暂停，不产生 seek。
///
/// 提示层现在挂在 `Player` 上（两个模式共用），这里用 [SeekHudOverlay] 单独验证
/// 渲染，拖动规则由 `seek_session_test.dart` 覆盖。

final List<int> forwards = [];
final List<int> backwards = [];

MediaPlayer _fakePlayer({Duration position = const Duration(seconds: 10)}) =>
    MediaPlayer(
      isInitializing: false,
      isPlaying: true,
      position: position,
      duration: const Duration(minutes: 5),
      buffer: Duration.zero,
      width: 0,
      height: 0,
      saveProgress: () async {},
      play: () async {},
      pause: () async {},
      backward: (seconds) async => backwards.add(seconds),
      forward: (seconds) async => forwards.add(seconds),
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
          body: Stack(
            children: [
              Provider<MediaPlayer>.value(
                value: _fakePlayer(),
                child: const ShortVideoView(),
              ),
              // 与 Player 里一致：提示层挂在模式分支之外
              Positioned.fill(
                child: SeekHudOverlay(controller: seekHub.hud),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 在指定位置双击（两次点击间隔 < 双击窗口）
Future<void> _doubleTapAt(WidgetTester tester, Offset position) async {
  await tester.tapAt(position);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tapAt(position);
  await tester.pump(const Duration(milliseconds: 60));
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  seekHub.reset();
}

void main() {
  setUp(() {
    forwards.clear();
    backwards.clear();
    seekHub.reset();
  });

  testWidgets('双击右侧 1/3: 快进并显示 "+Ns" 提示', (tester) async {
    await _setQueue(tester, 0);
    await _pumpView(tester);

    final size = tester.getSize(find.byType(ShortVideoView));
    await _doubleTapAt(tester, Offset(size.width * 0.85, size.height * 0.4));

    final step = useAppStore().state.seekStepSeconds;
    expect(forwards, [step], reason: '双击右侧应快进一步');
    expect(find.byIcon(Icons.fast_forward_rounded), findsOneWidget);
    expect(find.text('+${step}s'), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets('双击左侧 1/3: 快退并显示 "-Ns" 提示', (tester) async {
    await _setQueue(tester, 0);
    await _pumpView(tester);

    final size = tester.getSize(find.byType(ShortVideoView));
    await _doubleTapAt(tester, Offset(size.width * 0.15, size.height * 0.4));

    final step = useAppStore().state.seekStepSeconds;
    expect(backwards, [step], reason: '双击左侧应快退一步');
    expect(find.byIcon(Icons.fast_rewind_rounded), findsOneWidget);
    expect(find.text('-${step}s'), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets('双击中间 1/3: 只播放暂停, 不 seek', (tester) async {
    await _setQueue(tester, 0);
    await _pumpView(tester);

    final size = tester.getSize(find.byType(ShortVideoView));
    await _doubleTapAt(tester, Offset(size.width * 0.5, size.height * 0.4));

    expect(forwards, isEmpty);
    expect(backwards, isEmpty);

    await _teardown(tester);
  });
}
