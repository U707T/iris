import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/player_handoff.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:iris/utils/short_video.dart';

/// 模式切换的播放器交接测试:
/// 切换前必须能立刻暂停"即将被卸载"的播放器 (它的销毁是异步的),
/// 否则会出现两路声音 (操作过快时主模式和短视频模式同时出声)。

MediaPlayer _fakePlayer({void Function()? onPause}) => MediaPlayer(
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
      pause: () async => onPause?.call(),
      backward: (_) async {},
      forward: (_) async {},
      stepBackward: () async {},
      stepForward: () async {},
      seek: (_) async {},
    );

void main() {
  test('静音时暂停当前注册的播放器; 注销后不再暂停', () async {
    var paused = 0;
    final player = _fakePlayer(onPause: () => paused++);

    registerActivePlayer(player);
    expect(activeHandoffPlayer, same(player));

    await silenceActivePlayer();
    expect(paused, 1);

    unregisterActivePlayer(player);
    expect(activeHandoffPlayer, isNull);

    await silenceActivePlayer();
    expect(paused, 1);
  });

  test('旧宿主卸载不会清掉新宿主的注册', () async {
    var pausedOld = 0;
    var pausedNew = 0;
    final oldPlayer = _fakePlayer(onPause: () => pausedOld++);
    final newPlayer = _fakePlayer(onPause: () => pausedNew++);

    registerActivePlayer(oldPlayer);
    // 新宿主先注册, 旧宿主随后卸载 (元素树更新顺序不固定)
    registerActivePlayer(newPlayer);
    unregisterActivePlayer(oldPlayer);

    await silenceActivePlayer();
    expect(pausedOld, 0);
    expect(pausedNew, 1);

    unregisterActivePlayer(newPlayer);
  });

  test('播放器暂停抛错 (正在销毁) 时不影响调用方', () async {
    final player = _fakePlayer(onPause: () => throw StateError('disposed'));

    registerActivePlayer(player);
    await silenceActivePlayer();
    unregisterActivePlayer(player);
  });

  testWidgets('进入 / 退出短视频模式前会静音当前播放器 (防两路声音)', (tester) async {
    // 队列里需要有视频条目, 否则进入模式会直接返回
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

    var paused = 0;
    final player = _fakePlayer(onPause: () => paused++);

    // 模拟普通模式宿主注册了自己使用的播放器
    registerActivePlayer(player);

    await tester.runAsync(() async {
      enterShortVideoMode();
      await Future<void>.delayed(Duration.zero);
    });
    expect(usePlayerUiStore().state.isShortVideoMode, isTrue);
    expect(paused, 1, reason: '进入短视频模式前应静音普通模式播放器');

    // 重复调用 (连点 / 双击) 不应再静音: 此时注册的已经是短视频池,
    // 静音会把刚进入的短视频停掉
    await tester.runAsync(() async {
      enterShortVideoMode();
      await Future<void>.delayed(Duration.zero);
    });
    expect(paused, 1, reason: '重复进入不应静音短视频池');

    await tester.runAsync(() async {
      exitShortVideoMode();
      await Future<void>.delayed(Duration.zero);
    });
    expect(usePlayerUiStore().state.isShortVideoMode, isFalse);
    expect(paused, 2, reason: '退出短视频模式前应静音当前播放器');

    // 重复退出不应再静音: 否则会停掉刚挂载的普通模式播放器
    await tester.runAsync(() async {
      exitShortVideoMode();
      await Future<void>.delayed(Duration.zero);
    });
    expect(paused, 2, reason: '重复退出不应静音普通模式播放器');

    unregisterActivePlayer(player);
  });
}
