import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/models/store/play_queue_state.dart';
import 'package:iris/pages/player/control_bar/control_bar.dart';
import 'package:iris/pages/player/overlays/controls_overlay.dart';
import 'package:iris/pages/player/title_bar.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:provider/provider.dart';
// `StoreLocator` 定义在 flutter_zustand 的传递依赖 zustand 里：这里需要一个
// 「不会被卸载」的 locator 提供者（StoreScope 卸载时会 dispose 全局 locator，
// 同一个文件里的后续用例就会拿到已经 close 的 store）。
// ignore: depend_on_referenced_packages
import 'package:zustand/zustand.dart';

/// 控制层显隐的渲染契约：
/// - 收起 = 真的滑出屏幕外（不留一条能点的边）
/// - 收起后不吃指针（点击落到画面上，而不是看不见的按钮）
/// - 音频没有画面可看 → 控制层常驻
MediaPlayer _dummyPlayer() => MediaPlayer(
      isInitializing: false,
      isPlaying: true,
      position: Duration.zero,
      duration: const Duration(minutes: 10),
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

const Size _phone = Size(360, 800);

int _backgroundTaps = 0;

Future<void> _pump(
  WidgetTester tester, {
  required bool visible,
  ContentType type = ContentType.video,
  double viewPaddingTop = 0,
}) async {
  await tester.binding.setSurfaceSize(_phone);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  _backgroundTaps = 0;

  usePlayQueueStore().set(
    PlayQueueState(
      playQueue: [
        PlayQueueItem(
          file: FileItem(name: 'a', uri: 'a', type: type),
          index: 0,
        ),
      ],
      currentIndex: 0,
    ),
  );
  usePlayerUiStore().updateIsShowControl(visible);
  usePlayerUiStore().updateIsShowProgress(false);

  await tester.pumpWidget(
    // 不用 StoreScope: 它卸载时会 dispose 掉全局 StoreLocator,
    // 同一个文件里的下一个用例就会拿到 stream 已经 close 的 store。
    // StoreScope 实际提供的就只是一个 StoreLocator 依赖, 这里直接给一个。
    Provider<StoreLocator>.value(
      value: StoreLocator(),
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
            body: MediaQuery(
              // ControlBar 用 MediaQuery 的宽度选布局, 必须和实际约束一致,
              // 否则测到的是「桌面布局被塞进 360 宽」的假溢出。
              data: MediaQueryData(
                size: _phone,
                viewPadding: EdgeInsets.only(top: viewPaddingTop),
              ),
              child: Stack(
              children: [
                // 画面层：控制层收起来之后, 点击必须落在这里
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _backgroundTaps++,
                  ),
                ),
                Positioned.fill(
                  child: ControlsOverlay(
                    file: FileItem(name: 'a', uri: 'a', type: type),
                    title: 'a',
                    showControl: () {},
                    showControlForHover: (cb) async => await cb,
                  ),
                ),
              ],
            ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}



/// 每个用例结束把树拆掉（否则计时器/动画会漏到下一个用例）
Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  testWidgets('显示时: 标题栏与控制栏都在屏幕内', (tester) async {
    await _pump(tester, visible: true);

    final bar = tester.getRect(find.byType(ControlBar));
    final title = tester.getRect(find.byType(TitleBar));
    expect(bar.bottom, moreOrLessEquals(_phone.height), reason: '控制栏贴底');
    expect(bar.top, greaterThan(0));
    expect(title.top, greaterThanOrEqualTo(0));

  });

  testWidgets('收起时: 控制栏整体移出屏幕, 不留可点的边', (tester) async {
    await _pump(tester, visible: false);

    final bar = tester.getRect(find.byType(ControlBar));
    final title = tester.getRect(find.byType(TitleBar));

    // 老实现写死 bottom: -128, 而窄屏两行控制栏高 140px
    // → 屏幕底部留了 12px 可点的按钮条
    expect(
      bar.top,
      greaterThanOrEqualTo(_phone.height),
      reason: '控制栏必须完整滑出屏幕底部',
    );
    expect(title.bottom, lessThanOrEqualTo(0), reason: '标题栏必须完整滑出顶部');

  });

  testWidgets('收起时: 点击落到画面上（控制层不吃指针）', (tester) async {
    await _pump(tester, visible: false);

    // 底部一条（老实现残留按钮的地方）与中间都点一下
    await tester.tapAt(const Offset(180, 790));
    await tester.pump();
    await tester.tapAt(const Offset(180, 400));
    await tester.pump();

    expect(_backgroundTaps, 2, reason: '两次点击都应落到画面层');

  });

  testWidgets('显示时: 控制栏吃掉点击, 不误触画面', (tester) async {
    await _pump(tester, visible: true);

    await tester.tapAt(const Offset(180, 760));
    await tester.pump();

    expect(_backgroundTaps, 0);

  });

  testWidgets('刘海屏: 收起后标题栏不会停在状态栏那一条里', (tester) async {
    await _pump(tester, visible: false, viewPaddingTop: 44);

    final title = tester.getRect(find.byType(TitleBar));
    // 安全区 44px 必须在滑出量里一起算掉, 否则标题栏正好停在 0..44 这一条
    expect(
      title.bottom,
      lessThanOrEqualTo(0),
      reason: '收起时标题栏要连安全区一起滑出屏幕',
    );

    // 显示时仍然让出安全区
    await _pump(tester, visible: true, viewPaddingTop: 44);
    expect(tester.getRect(find.byType(TitleBar)).top, greaterThanOrEqualTo(44));

    await _teardown(tester);
  });

  testWidgets('音频始终保留控制层（没有画面可看）', (tester) async {
    await _pump(tester, visible: false, type: ContentType.audio);

    final bar = tester.getRect(find.byType(ControlBar));
    final title = tester.getRect(find.byType(TitleBar));
    expect(bar.bottom, moreOrLessEquals(_phone.height));
    expect(title.top, greaterThanOrEqualTo(0));

  });
}
