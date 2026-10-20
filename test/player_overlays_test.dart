import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/overlays/empty_player_hint.dart';
import 'package:iris/pages/player/overlays/playback_error_overlay.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// 播放器空状态 / 播放失败浮层的冒烟测试:
/// 这两个浮层在 v2.4.0 加进了主界面 Stack, 任何一个抛异常都会让整屏变黑。

MediaPlayer _fakePlayer({
  String? error,
  Future<void> Function()? retry,
}) =>
    MediaPlayer(
      isInitializing: false,
      isPlaying: false,
      error: error,
      retry: retry,
      externalSubtitles: const [],
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
    );

Future<void> _pump(WidgetTester tester, MediaPlayer player) async {
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
            value: player,
            child: const Stack(
              children: [
                EmptyPlayerHint(),
                PlaybackErrorOverlay(),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('空队列: 显示首次启动提示', (tester) async {
    await _pump(tester, _fakePlayer());

    expect(find.text('Drop a file here, or press Ctrl+O to open'), findsOneWidget);
    // 没有错误时不显示重试按钮
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('播放失败: 显示错误原因, 重试按钮可用', (tester) async {
    var retries = 0;
    await _pump(
      tester,
      _fakePlayer(
        error: 'Failed to open file',
        retry: () async => retries++,
      ),
    );

    expect(find.text('Unable to play this file'), findsOneWidget);
    expect(find.text('Failed to open file'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(retries, 1);
  });

  testWidgets('队列只有一条时, 错误浮层不显示「下一个」', (tester) async {
    await tester.runAsync(() async {
      await usePlayQueueStore().update(
        playQueue: [
          PlayQueueItem(
            file: FileItem(name: 'v0', uri: 'v0', type: ContentType.video),
            index: 0,
          ),
        ],
        index: 0,
      );
    });

    await _pump(tester, _fakePlayer(error: 'boom', retry: () async {}));

    expect(find.text('Next'), findsNothing);
  });
}
