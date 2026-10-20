import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/progress.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_history_store.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/utils/wait_for_first_frame.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 播放器池大小: 上一条 / 当前 / 下一条
const int _shortVideoPoolSize = 3;

/// media_kit_video 的视频输出通道 (Android 兜底校正画面尺寸用, 见 [_syncVideoOutputSize])
const MethodChannel _videoOutputChannel =
    MethodChannel('com.alexmercerind/media_kit_video');


/// 单个播放器槽位
class ShortVideoSlot {
  ShortVideoSlot({required this.player, required this.controller});

  final Player player;
  final VideoController controller;

  /// 承载的信息流下标 (null = 空闲)
  int? feedIndex;

  /// 对应文件 (用于保存进度)
  FileItem? loadedFile;

  /// 是否正在装载
  bool initializing = false;

  /// 是否真正播放过 (未播放过的预载槽位不需要保存进度)
  bool played = false;

  /// 装载序号, 用于丢弃过期的异步结果
  int token = 0;

  /// 是否有等待执行的装载请求
  bool pendingOpen = false;

  /// 装载失败原因 (null = 正常), 由界面显示 + 重试
  String? error;
}

/// 短视频模式使用的预载播放器池:
/// 同时保持 3 个播放器实例 (上一条 / 当前 / 下一条),
/// 滑动切换时直接复用已装载的实例, 实现无缝切换。
class ShortVideoPool extends ChangeNotifier {
  ShortVideoPool({required this.buildMedia}) {
    for (var i = 0; i < _shortVideoPoolSize; i++) {
      final player = Player();
      slots.add(
        ShortVideoSlot(player: player, controller: VideoController(player)),
      );
    }
  }

  final Media Function(FileItem file) buildMedia;
  final List<ShortVideoSlot> slots = [];

  List<PlayQueueItem> items = const [];
  int currentFeedIndex = 0;

  /// 用户是否主动暂停了当前视频 (划到新视频时重置)
  bool userPaused = false;

  ShortVideoSlot? _active;
  bool _ensureActivePending = false;
  bool _applyScheduled = false;
  bool disposed = false;

  /// 待保存的进度 (在 build 中收集, 帧后执行)
  final List<({FileItem file, Duration position, Duration duration})>
      _pendingSaves = [];

  ShortVideoSlot? slotFor(int feedIndex) {
    for (final slot in slots) {
      if (slot.feedIndex == feedIndex) return slot;
    }
    return null;
  }

  /// 最近一次处于活动状态的槽位 (当前下标暂无槽位时的兜底, 避免误用第一个槽位的画面)
  ShortVideoSlot? get activeSlot => _active;

  /// 根据当前下标决定各槽位的装载目标 (在 build 中调用)
  void reconcile(int current, List<PlayQueueItem> items) {
    if (disposed) return;

    // 队列变化时校验槽位承载的文件是否仍然匹配
    if (!identical(items, this.items)) {
      for (final slot in slots) {
        final index = slot.feedIndex;
        if (index == null) continue;
        if (index >= items.length || items[index].file != slot.loadedFile) {
          _collectSlotSave(slot);
          slot.pendingOpen = false;
          slot.played = false;
          slot.error = null;
          slot.feedIndex = null;
          // 立即作废仍在飞行中的装载 / 尺寸同步 (token 递增), 并复位装载标记:
          // 槽位随后可能被重新分配给别的下标, 旧一代的异步结果不能落到新一代上
          // (先播放旧视频 / 提前熄灭加载指示)。
          slot.token++;
          slot.initializing = false;
        }
      }
    }

    this.items = items;
    currentFeedIndex = current;

    if (items.isEmpty || current < 0 || current >= items.length) {
      _maybeSchedule();
      return;
    }

    // 需要就绪的下标: 当前 / 下一条 / 上一条
    final needed = <int>{};
    for (final offset in const [0, 1, -1]) {
      final index = current + offset;
      if (index >= 0 && index < items.length) needed.add(index);
    }

    // 为缺失的下标分配槽位 (当前视频优先)
    for (final offset in const [0, 1, -1]) {
      final want = current + offset;
      if (want < 0 || want >= items.length) continue;
      if (slotFor(want) != null) continue;

      final slot = _pickReusable(needed);
      if (slot == null) continue;

      // 复用前捕获旧视频的播放进度
      _collectSlotSave(slot);

      // 立即静音被复用的槽位 (正常情况下它已经不是活动槽位, 这里是兜底:
      // 避免上一个视频的声音延续到新视频开始装载)
      if (slot.player.state.playing) {
        unawaited(slot.player.pause().catchError((_) {}));
      }

      slot.feedIndex = want;
      slot.loadedFile = items[want].file;
      slot.initializing = true;
      slot.played = false;
      slot.pendingOpen = true;
      // 递增 token: 作废该槽位上一代 (旧下标) 仍在飞行中的异步操作
      slot.token++;
    }

    // 激活当前下标所在槽位
    final newActive = slotFor(current);
    if (newActive != null && newActive != _active) {
      _active = newActive;
      _ensureActivePending = true;
      userPaused = false;
    }

    _maybeSchedule();
  }

  void _maybeSchedule() {
    if (_applyScheduled || disposed) return;
    if (!_ensureActivePending &&
        _pendingSaves.isEmpty &&
        !slots.any((slot) => slot.pendingOpen)) {
      return;
    }
    _applyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyScheduled = false;
      applyPending();
    });
  }

  /// 执行 reconcile 记录的装载 / 播放动作 (帧后调用)
  void applyPending() {
    if (disposed) return;

    // 保存队列变化时收集的进度
    _flushPendingSaves();

    // 打开待装载的槽位, 当前视频优先
    final pending = slots.where((slot) => slot.pendingOpen).toList()
      ..sort((a, b) => (a.feedIndex == currentFeedIndex ? 0 : 1)
          .compareTo(b.feedIndex == currentFeedIndex ? 0 : 1));
    for (final slot in pending) {
      slot.pendingOpen = false;
      unawaited(_openSlot(slot));
    }

    final active = slotFor(currentFeedIndex);

    // 活动槽位已就绪则立即开始播放 (用户主动暂停过则跳过)
    if (_ensureActivePending) {
      _ensureActivePending = false;
      if (active != null && !active.initializing && !userPaused) {
        unawaited(active.player.play().catchError((_) {}));
        active.played = true;
      }
      // 兜底: 即将展示这条视频时再校正一次画面尺寸 (Android, 幂等)
      if (active != null) {
        unawaited(_syncVideoOutputSize(active, token: active.token));
      }
    }

    // 暂停其它槽位, 避免上一个视频继续出声
    if (active != null) {
      for (final slot in slots) {
        if (slot != active && slot.player.state.playing) {
          unawaited(slot.player.pause().catchError((_) {}));
        }
      }
    }
  }

  ShortVideoSlot? _pickReusable(Set<int> needed) {
    // 优先空闲槽位
    for (final slot in slots) {
      if (slot.feedIndex == null) return slot;
    }
    // 其次复用非活动且不再需要的槽位
    for (final slot in slots) {
      if (slot != _active && !needed.contains(slot.feedIndex)) return slot;
    }
    for (final slot in slots) {
      if (!needed.contains(slot.feedIndex)) return slot;
    }
    return null;
  }

  Future<void> _openSlot(ShortVideoSlot slot) async {
    final file = slot.loadedFile;
    if (file == null) return;

    final token = ++slot.token;
    slot.error = null;
    try {
      // 视频输出必须先于 open 就绪。
      // 播放器刚创建时 VideoController 的视频输出 (纹理 / 画面尺寸) 与 open 是
      // 并行初始化的; 若视频先打开, 包内基于 videoParams 的尺寸同步会因为视频
      // 输出还不存在而丢失, 之后画面一直按初始的 1x1 比例显示 —— 表现为
      // "短视频模式比例很奇怪", 切换视频或重进模式才恢复。这里显式等待。
      await _ensureVideoOutputReady(slot.controller);
      if (disposed || token != slot.token) return;

      // 先应用循环 / 倍速 / 音量等设置, 避免开始播放时短暂使用默认值
      final appState = useAppStore().state;
      await slot.player.setPlaylistMode(PlaylistMode.loop);
      await slot.player.setRate(appState.rate);
      await slot.player.setVolume(
          appState.isMuted ? 0 : appState.volume.toDouble());
      if (disposed || token != slot.token) return;

      // 一律以暂停方式打开: 由下面的显式 play() 决定是否开始播放。
      // 不能依赖 open(play: true) —— 打开是异步的, 若这期间退出短视频模式,
      // 视频仍会在装载完成后自动出声, 与新模式的播放器重叠 (操作过快时
      // "主模式和短视频模式同时出声" 的成因之一)。
      await slot.player.open(buildMedia(file), play: false);
      if (disposed || token != slot.token) return;

      // 等视频输出出首帧再往下走 (包含"成为当前视频后开始播放"),
      // 否则会出现"先响声音、画面还黑着"; 预载槽位也顺手把首帧解出来,
      // 滑动切过去时画面是现成的。
      await waitForFirstFrame(slot.controller);
      if (disposed || token != slot.token) return;

      slot.initializing = false;
      notifyListeners();

      // 兜底: 打开后校正一次视频输出尺寸 (Android, 幂等, 正常情况下是空操作)
      unawaited(_syncVideoOutputSize(slot, token: token, delay: true));

      // 已成为当前视频则开始播放 (用户主动暂停过 / 已被卸载则跳过)
      if (!userPaused && slotFor(currentFeedIndex) == slot) {
        unawaited(slot.player.play().catchError((_) {}));
        slot.played = true;
      }

      // 个别情况下 mpv 不上报 duration, 兜底轮询并主动刷新界面
      if (slot.player.state.duration == Duration.zero) {
        unawaited(_ensureSlotDuration(slot, token));
      }
    } catch (e) {
      logger('Short video pool open error: $e');
      if (!disposed && token == slot.token) {
        slot.initializing = false;
        slot.error = e.toString();
        notifyListeners();
      }
    }
  }

  /// 重新装载一个失败的槽位 (界面上的"重试")。
  /// 只重置错误/装载标记, 真正的 open 仍走帧后调度, 不在 build 期间碰播放器。
  void reopen(ShortVideoSlot slot) {
    if (disposed) return;
    slot.error = null;
    slot.initializing = true;
    slot.played = false;
    slot.pendingOpen = true;
    // 作废该槽位上一代正在飞的 open / 尺寸同步
    slot.token++;
    userPaused = false;
    // 立刻刷新界面 (收起错误卡片 / 显示加载指示)
    notifyListeners();
    _maybeSchedule();
  }

  /// 等待视频输出初始化完成 (带超时兜底: 个别平台上视频输出不可用时也不能卡死)
  Future<void> _ensureVideoOutputReady(VideoController controller) async {
    try {
      await controller.platform.future.timeout(const Duration(seconds: 2));
    } catch (e) {
      logger('Short video pool: video output not ready: $e');
    }
  }

  /// Android 兜底: 校正视频输出的画面尺寸。
  ///
  /// 正常情况下 [VideoController] 收到 videoParams 会自动同步尺寸; 但在
  /// "视频输出创建晚于 open" 等竞态下, 这次同步会丢失, 之后画面一直按初始的
  /// 1x1 比例显示 (表现为短视频模式比例很奇怪, 切换视频 / 重进模式才恢复)。
  /// 这里在装载完成后和即将展示时各补一次: 尺寸一致时原生侧会直接忽略,
  /// 因此重复调用是安全且几乎零成本的。
  Future<void> _syncVideoOutputSize(
    ShortVideoSlot slot, {
    required int token,
    bool delay = false,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      if (delay) {
        // 给包内的尺寸同步留出时间, 避免和它同时写入
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (disposed || token != slot.token) return;
      }
      // 仍在装载 (尺寸可能还是上一条视频的) 时跳过
      if (slot.initializing) return;

      final params = slot.player.state.videoParams;
      final dw = params.dw;
      final dh = params.dh;
      if (dw == null || dh == null || dw == 0 || dh == 0) return;

      // 与 media_kit 的 AndroidVideoController 保持一致: 90/270 度旋转时宽高互换
      final rotate = params.rotate ?? 0;
      final int width;
      final int height;
      if (rotate == 0 || rotate == 180) {
        width = dw;
        height = dh;
      } else {
        width = dh;
        height = dw;
      }

      final handle = await slot.player.handle;
      if (disposed || token != slot.token) return;
      await _videoOutputChannel.invokeMethod(
        'VideoOutputManager.SetSurfaceSize',
        {
          'handle': handle.toString(),
          'width': width.toString(),
          'height': height.toString(),
        },
      );
    } catch (e) {
      logger('Short video pool: sync video output size failed: $e');
    }
  }

  /// duration 兜底: 短时间内轮询同步状态, 拿到值后通知界面刷新
  Future<void> _ensureSlotDuration(ShortVideoSlot slot, int token) async {
    for (var attempt = 0; attempt < 4; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (disposed || token != slot.token) return;
      if (slot.player.state.duration != Duration.zero) {
        notifyListeners();
        return;
      }
      if (attempt == 1) {
        // 温和触发一次属性刷新 (跳到当前位置)
        unawaited(slot.player.seek(slot.player.state.position).catchError((_) {}));
      }
    }
  }

  /// 收集槽位的播放进度 (在 reconcile 中调用, 帧后统一写入)
  void _collectSlotSave(ShortVideoSlot slot) {
    final file = slot.loadedFile;
    if (file == null || !slot.played) return;

    final state = slot.player.state;
    if (state.duration == Duration.zero) return;

    _pendingSaves.add((
      file: file,
      position: state.position,
      duration: state.duration,
    ));
  }

  /// 写入已收集的进度
  void _flushPendingSaves() {
    if (_pendingSaves.isEmpty) return;
    for (final save in _pendingSaves) {
      useHistoryStore().add(Progress(
        dateTime: DateTime.now().toUtc(),
        position: save.position,
        duration: save.duration,
        file: save.file,
      ));
    }
    _pendingSaves.clear();
  }

  /// 保存某个槽位的播放进度 (立即写入, 调用方需保证不在 build 期间)
  void saveSlotProgress(ShortVideoSlot slot) {
    _collectSlotSave(slot);
    _flushPendingSaves();
  }

  /// 立即静音所有槽位 (模式切换前调用, 见 player_handoff.dart)。
  /// 销毁是异步的 (要等播放器初始化 / 锁), 先暂停才能保证不和新播放器同时出声。
  void silence() {
    for (final slot in slots) {
      if (slot.player.state.playing) {
        unawaited(slot.player.pause().catchError((_) {}));
      }
    }
  }

  @override
  void dispose() {
    disposed = true;
    for (final slot in slots) {
      if (slot.played) saveSlotProgress(slot);
      // 先立即静音, 再异步销毁
      if (slot.player.state.playing) {
        unawaited(slot.player.pause().catchError((_) {}));
      }
      unawaited(slot.player.dispose().catchError((_) {}));
    }
    super.dispose();
  }
}

