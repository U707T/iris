import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/models/store/play_queue_state.dart';
import 'package:iris/pages/player/control_bar/control_bar.dart';
import 'package:iris/store/use_play_queue_store.dart';
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

Future<void> _pumpControlBar(WidgetTester tester, double width) async {
  await tester.binding.setSurfaceSize(Size(width, 400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

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
        PlayQueueItem(
          file: FileItem(
            name: 'b.mp4',
            uri: 'b.mp4',
            type: ContentType.video,
          ),
          index: 1,
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
  // 360 是常见手机宽度; 640/900 覆盖原来的「平板单行」区间;
  // 1024 进入桌面单行。任何一档溢出都会让测试失败。
  for (final width in <double>[360, 448, 640, 900, 1024, 1200, 1280]) {
    testWidgets('控制栏在 ${width.toInt()} 宽不溢出', (tester) async {
      await _pumpControlBar(tester, width);
      expect(tester.takeException(), isNull);
    });
  }
}
