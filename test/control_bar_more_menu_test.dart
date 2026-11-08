import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/globals.dart' show moreMenuKey;
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/models/store/play_queue_state.dart';
import 'package:iris/pages/player/control_bar/control_bar.dart';
import 'package:iris/store/use_play_queue_store.dart';
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

/// 「更多」菜单的分组顺序:
/// 打开内容 → 画面与方向 → 播放与队列 → 应用, 组间一条分隔线。
///
/// 断言用 y 坐标而不是直接读 itemBuilder 的输出 —— 后者只能证明"代码里排成
/// 什么样", 前者证明"用户看到的是什么顺序", 分隔线也一起验。
void main() {
  setUp(() {
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
  });

  testWidgets('窄屏「更多」菜单按四组排列, 组间有分隔线', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
                  data: const MediaQueryData(size: Size(360, 400)),
                  child: SizedBox(
                    width: 360,
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

    await tester.tap(find.byKey(moreMenuKey));
    await tester.pumpAndSettle();

    double top(String label) => tester.getTopLeft(find.text(label)).dy;

    // 组 1 打开内容: 打开文件 → 打开链接 → 存储(窄屏才在菜单里)
    expect(top('打开文件'), lessThan(top('打开链接')));
    expect(top('打开链接'), lessThan(top('存储')));

    // 组 2 画面与方向: 截图 → 旋转 / 翻转 → (桌面才有屏幕方向) → 全屏
    expect(top('存储'), lessThan(top('截图')));
    expect(top('截图'), lessThan(top('旋转 / 翻转')));

    // 组 3 播放与队列: 播放速度 → 音轨 → 短视频模式 → 播放统计
    expect(top('旋转 / 翻转'), lessThan(top('播放速度: 1.0X')));
    expect(top('播放速度: 1.0X'), lessThan(top('音轨')));
    expect(top('音轨'), lessThan(top('短视频模式')));
    expect(top('短视频模式'), lessThan(top('播放统计')));

    // 组 4 应用: 快捷键(桌面) → 历史 → 设置 → 退出, 退出永远垫底
    expect(top('播放统计'), lessThan(top('历史')));
    expect(top('历史'), lessThan(top('设置')));
    expect(top('设置'), lessThan(top('退出')));

    // 四组各有内容 → 3 条分隔线, 不会出现首条 / 末条分隔线
    expect(find.byType(PopupMenuDivider), findsNWidgets(3));
  });
}
