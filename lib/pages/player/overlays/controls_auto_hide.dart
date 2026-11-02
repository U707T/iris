import 'dart:async';

/// 播放器控制层（标题栏 + 控制栏 + 迷你进度）的自动隐藏调度。
///
/// ## 为什么要把这件事单独拎出来
///
/// v2.6.1 之前这套逻辑散在 `Player.build` 的两个 `Timer`、四个布尔量
/// （isShowControl / isShowProgress / isHovering / isSeeking）和二十多个手动
/// 调用 `resetTimer()` 的按钮之间。规则只有一条「到点后如果没在拖、没悬停就
/// 收起」，其余全靠各处在动作末尾补一次重置。于是下面这些问题是**必然**的：
///
/// | 现象 | 根因 |
/// |---|---|
/// | 暂停 / 播完，控制栏 5 秒后照样消失 | 计时器不看播放状态 |
/// | 打开倍速菜单、播放队列，控制栏在弹层底下自己收掉 | 弹层期间只有部分入口挂得住 |
/// | 指针停在控制栏上，到点后计时器直接停摆 | 到点发现悬停就 return，不重新计时 |
/// | 关掉「自动隐藏」后，方向键唤出的迷你进度再也不消失 | 迷你进度和开关绑在一起 |
///
/// ## 现在的口径（对齐 YouTube / VLC / mpv / PotPlayer / IINA）
///
/// 1. **只在播放中倒计时**：暂停、播完、出错、无媒体、音频文件 → 控制栏常驻；
/// 2. **正在被使用时不计时**：指针停在控件上、拖动 seek、弹层盖在上面；
/// 3. **任何交互都重新计时**：点击、按键、滚轮、鼠标移动，一律走 [show]；
/// 4. **迷你进度是瞬时读数**：不受「自动隐藏」开关影响，永远自己消失；
/// 5. 状态本身仍然存在 `PlayerUiStore`（`isShowControl` / `isShowProgress`），
///    这里只负责「什么时候该收起」，不新增第二份真相。
class ControlsAutoHide {
  ControlsAutoHide({
    required this.readControls,
    required this.writeControls,
    required this.readMinimal,
    required this.writeMinimal,
    this.delay = const Duration(seconds: 5),
  });

  /// 读取 / 写入实际显示状态（接到 `PlayerUiStore` 上，测试里换成局部变量）
  final bool Function() readControls;
  final void Function(bool visible) writeControls;
  final bool Function() readMinimal;
  final void Function(bool visible) writeMinimal;

  /// 控制隐藏延迟（设置里的「隐藏延迟」）
  Duration delay;

  /// 播放器是否正在播放。暂停 / 播完时主流播放器会让控制栏常驻。
  bool playing = true;

  /// 设置里的「自动隐藏控制栏」开关
  bool enabled = true;

  /// 指针停在标题栏 / 控制栏上（桌面端）
  bool hovering = false;

  /// 正在拖动 seek（画面横滑 / 进度条 / 双击连按）
  bool seeking = false;

  /// 有弹层 / 菜单 / 对话框盖在播放器上面
  bool overlayOpen = false;

  /// 当前宿主是否参与（短视频模式没有控制栏，挂起）
  bool active = true;

  Timer? _controlsTimer;
  Timer? _minimalTimer;
  bool _disposed = false;

  /// 现在允许自动收起控制栏吗
  bool get canHide =>
      active && enabled && playing && !hovering && !seeking && !overlayOpen;

  /// 唤出控制栏并重新计时（点击画面 / 按键 / 滚轮 / 鼠标移动都走这里）
  void show() {
    if (_disposed) return;
    _writeMinimal(false); // 完整控制栏出现后，迷你进度是多余的
    _writeControls(true);
    sync();
  }

  /// 只看进度（方向键快进、画面横滑）：控制栏本来就在屏幕上时只续期
  void showMinimal() {
    if (_disposed) return;
    if (readControls()) {
      sync();
      return;
    }
    _writeMinimal(true);
    sync();
  }

  /// 立即收起（单击画面 / 返回键）
  void hide() {
    if (_disposed) return;
    _cancelTimers();
    _writeMinimal(false);
    _writeControls(false);
  }

  /// 外部状态变化（播放状态 / 设置 / 悬停 / 拖动 / 弹层）后重新评估。
  ///
  /// 任何一次调用都等于「从现在重新计时」—— 交互本身就是重置信号，
  /// 不需要调用方再记一个 deadline。
  void sync() {
    if (_disposed) return;
    _armControls();
    _armMinimal();
  }

  void _armControls() {
    if (!canHide || !readControls()) {
      _controlsTimer?.cancel();
      _controlsTimer = null;
      return;
    }

    _controlsTimer?.cancel();
    _controlsTimer = Timer(delay, () {
      _controlsTimer = null;
      if (!readControls() || !canHide) return;
      _writeControls(false);
      _writeMinimal(false);
    });
  }

  void _armMinimal() {
    _minimalTimer?.cancel();
    _minimalTimer = null;
    if (!active || !readMinimal()) return;
    // 拖动中不收起：它是拖动时唯一的读数来源。松手后由 sync() 重新计时。
    if (seeking || hovering) return;
    _minimalTimer = Timer(delay, () {
      _minimalTimer = null;
      if (!readMinimal()) return;
      _writeMinimal(false);
    });
  }

  /// 只在值真的变化时写 store。
  ///
  /// 桌面端鼠标每移动一像素就会走一次 [show]，而 zustand 的 `set` 无论值是否
  /// 相同都会广播一次变更（`StoreLocator.changes`）—— 不加这个判断的话，
  /// 鼠标划过播放器会让所有订阅 store 的组件每帧重建。
  void _writeControls(bool visible) {
    if (readControls() == visible) return;
    writeControls(visible);
  }

  void _writeMinimal(bool visible) {
    if (readMinimal() == visible) return;
    writeMinimal(visible);
  }

  void _cancelTimers() {
    _controlsTimer?.cancel();
    _controlsTimer = null;
    _minimalTimer?.cancel();
    _minimalTimer = null;
  }

  void dispose() {
    _disposed = true;
    _cancelTimers();
  }
}
