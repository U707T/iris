import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/models/store/play_queue_state.dart';
import 'package:iris/pages/player/control_bar/control_bar.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/utils/platform.dart';
import 'package:iris/widgets/panel.dart';
import 'package:provider/provider.dart';

void _noop() {}

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

Future<void> _pumpControlBar(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
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
                data: MediaQueryData(size: size),
                child: SizedBox(
                  width: size.width,
                  height: 220,
                  child: ControlBar(
                    showControl: _noop,
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

double _top(WidgetTester tester, String label) =>
    tester.getTopLeft(find.text(label)).dy;

void _expectInOrder(WidgetTester tester, List<String> labels) {
  final ys = [for (final label in labels) _top(tester, label)];
  expect(
    ys,
    orderedEquals([...ys]..sort()),
    reason: '菜单顺序: ${[for (var i = 0; i < labels.length; i++) '${labels[i]}@${ys[i]}']}',
  );
}

void main() {
  setUp(() {
    // 控制栏里的移动端条目只在移动端出现; 测试跑在 Linux 宿主上,
    // 不覆盖平台判定, 测到的永远是桌面布局。
    debugIsDesktopOverride = false;
  });
  tearDown(() => debugIsDesktopOverride = null);

  testWidgets('窄屏「更多」是底部 sheet, 四组动作按顺序排列', (tester) async {
    await _pumpControlBar(tester, const Size(360, 1200));

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();

    // 四组各一块 PanelSection; sheet 不用分隔线
    expect(find.byType(PanelSection), findsNWidgets(4));
    expect(find.byType(PopupMenuDivider), findsNothing);

    _expectInOrder(tester, const [
      // 打开内容（存储已占控制栏第二个位置，不再重复）
      '打开文件',
      '打开链接',
      // 画面与方向
      '截图',
      '旋转 / 翻转',
      '缩放',
      '屏幕方向',
      // 播放与队列（音量从控制栏收进来）
      '播放速度',
      '音轨',
      '音量',
      '刷新播放列表',
      '播放统计',
      // 应用（短视频已占控制栏第四个位置）
      '历史',
      '设置',
      '退出',
    ]);
  });

  testWidgets('窄屏「更多 → 音量」打开滑条对话框', (tester) async {
    await _pumpControlBar(tester, const Size(360, 1200));

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('音量'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('音量'));
    await tester.pumpAndSettle();

    // 控制栏自己还有一条进度 Slider；音量对话框里的那条 max 是 100
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w is Slider && w.max == 100),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('宽屏「更多」是两级菜单, 一级四组 / 二级是动作', (tester) async {
    debugIsDesktopOverride = true;
    await _pumpControlBar(tester, const Size(1280, 900));

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();

    // 一级：只有四个分组
    _expectInOrder(tester, const ['打开内容', '画面与方向', '播放与队列', '应用']);

    // 二级：打开内容（桌面单行没有存储按钮，菜单里保留）
    await tester.tap(find.text('打开内容'));
    await tester.pumpAndSettle();
    _expectInOrder(tester, const ['打开文件', '打开链接', '存储']);

    // 二级：画面与方向
    await tester.tap(find.text('画面与方向'));
    await tester.pumpAndSettle();
    _expectInOrder(tester, const ['截图', '旋转 / 翻转', '缩放', '进入全屏']);

    // 二级：播放与队列
    await tester.tap(find.text('播放与队列'));
    await tester.pumpAndSettle();
    _expectInOrder(tester, const [
      '播放速度',
      '音轨',
      '短视频模式',
      '刷新播放列表',
      '播放统计',
    ]);

    // 二级：应用
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    _expectInOrder(tester, const ['快捷键', '历史', '设置', '退出']);
  });
}
