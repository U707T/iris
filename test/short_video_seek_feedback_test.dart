import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/short_video/short_video_view.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:provider/provider.dart';

/// 短视频模式双击快进 / 快退提示测试:
/// - 双击右侧 25% -> 快进 seekStepSeconds 秒, 画面中央短暂显示 "+Ns"
/// - 双击左侧 25% -> 快退 seekStepSeconds 秒, 显示 "-Ns"
/// - 提示约 700ms 后自动消失

/// 记录 forward / backward 的步长 (秒)
final List<int> forwards = [];
final List<int> backwards = [];

MediaPlayer _fakePlayer() => MediaPlayer(
      isInitializing: false,
      isPlaying: true,
      externalSubtitles: const [],
      position: const Duration(seconds: 10),
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

/// 在指定位置双击 (两次点击间隔 < 双击窗口)
Future<void> _doubleTapAt(WidgetTester tester, Offset position) async {
  await tester.tapAt(position);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tapAt(position);
  await tester.pump(const Duration(milliseconds: 60));
}

void main() {
  setUp(() {
    forwards.clear();
    backwards.clear();
  });

  testWidgets('双击右侧: 快进并显示 "+Ns" 提示, 随后自动消失', (tester) async {
    await _setQueue(tester, 0);
    await _pumpView(tester);

    final size = tester.getSize(find.byType(ShortVideoView));
    await _doubleTapAt(tester, Offset(size.width * 0.85, size.height * 0.4));

    final step = useAppStore().state.seekStepSeconds;
    expect(forwards, [step], reason: '双击右侧应快进一步');
    expect(find.byIcon(Icons.fast_forward_rounded), findsOneWidget);
    expect(find.text('+${step}s'), findsOneWidget);

    // 提示 700ms 后自动收起
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(find.text('+${step}s'), findsNothing);
  });

  testWidgets('双击左侧: 快退并显示 "-Ns" 提示', (tester) async {
    await _setQueue(tester, 0);
    await _pumpView(tester);

    final size = tester.getSize(find.byType(ShortVideoView));
    await _doubleTapAt(tester, Offset(size.width * 0.15, size.height * 0.4));

    final step = useAppStore().state.seekStepSeconds;
    expect(backwards, [step], reason: '双击左侧应快退一步');
    expect(find.byIcon(Icons.fast_rewind_rounded), findsOneWidget);
    expect(find.text('-${step}s'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(find.text('-${step}s'), findsNothing);
  });
}
