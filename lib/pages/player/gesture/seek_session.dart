import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/gesture/seek_gesture.dart';
import 'package:iris/store/use_play_queue_store.dart';

/// A drag owns one media entry and one preview until it settles or is cancelled.
class SeekSession {
  SeekSession({
    required this.readPlayer,
    required this.preview,
    this.readIdentity,
    this.settleDelay = const Duration(milliseconds: 350),
    this.maxSettleWait = const Duration(milliseconds: 1500),
  });

  final MediaPlayer Function() readPlayer;
  final ValueNotifier<Duration?> preview;
  final Object? Function()? readIdentity;
  final Duration settleDelay;
  final Duration maxSettleWait;
  static final _owners = Expando<SeekSession>();
  Timer? _settleTimer;
  bool _alive = true;
  bool _active = false;
  bool _resume = false;
  int _session = 0;
  Object? _identity;
  Duration _base = Duration.zero;
  Duration? _target;
  Duration? _pending;
  Duration? _lastFlushed;
  Future<void>? _flushing;

  bool get isActive => _active;
  Duration get base => _base;
  Duration? get target => _target;
  bool get wasPlaying => _resume;

  Object? _currentIdentity() {
    if (readIdentity != null) return readIdentity!();
    final player = readPlayer();
    if (player is! MediaKitPlayer) return player;
    final queue = usePlayQueueStore().state;
    final entry = queue.playQueue.indexWhere(
      (e) => e.index == queue.currentIndex,
    );
    return (
      player.player,
      queue.currentIndex,
      entry < 0 ? null : queue.playQueue[entry].file,
    );
  }

  bool _current(int session) =>
      _alive && session == _session && _identity == _currentIdentity();

  void _clearOwnedPreview() {
    if (_owners[preview] != this) return;
    _owners[preview] = null;
    preview.value = null;
  }

  void start(Duration from) {
    if (!_alive) return;
    _session++;
    _identity = _currentIdentity();
    _active = true;
    _base = from;
    _target = from;
    _pending = null;
    _lastFlushed = null;
    _flushing = null;
    _settleTimer?.cancel();
    _settleTimer = null;
    _owners[preview] = this;
    preview.value = from;
    final player = readPlayer();
    _resume = player.isPlaying;
    if (_resume) unawaited(player.pause().catchError((_) {}));
  }

  void seekTo(Duration target) {
    if (!_active || !_current(_session)) return;
    final clamped = clampSeekTarget(target, readPlayer().duration);
    if (clamped == _target && _pending == null) return;
    _target = clamped;
    _pending = clamped;
    preview.value = clamped;
    _settleTimer?.cancel();
    _settleTimer = Timer(settleDelay, _flush);
  }

  void dragTo(double dxPixels, {double screenWidth = 0}) {
    if (!_active || !_current(_session)) return;
    seekTo(
      seekTargetFor(
        base: _base,
        dxPixels: dxPixels,
        duration: readPlayer().duration,
        screenWidth: screenWidth,
      ),
    );
  }

  void _flush() {
    _settleTimer?.cancel();
    _settleTimer = null;
    final target = _pending;
    _pending = null;
    if (target == null || !_active || !_current(_session)) return;
    _lastFlushed = target;
    _flushing = _seekSafely(readPlayer(), target);
  }

  Future<void> _seekSafely(MediaPlayer player, Duration target) async {
    try {
      await player.seek(target).timeout(maxSettleWait);
    } catch (_) {}
  }

  void end() => _finish(clearImmediately: false);
  void cancel() => _finish(clearImmediately: true);

  void _finish({required bool clearImmediately}) {
    if (!_active) return;
    _settleTimer?.cancel();
    _settleTimer = null;
    final resume = _resume;
    final target = _target;
    final flushed = target == _lastFlushed ? _flushing : null;
    _active = false;
    _resume = false;
    _pending = null;
    final session = ++_session;
    if (clearImmediately) _clearOwnedPreview();
    if (target == null || !_current(session)) {
      _clearOwnedPreview();
      return;
    }
    unawaited(_settle(target, resume, session, flushed));
  }

  Future<void> _settle(
    Duration target,
    bool resume,
    int session,
    Future<void>? flushed,
  ) async {
    if (flushed != null) {
      await flushed;
    } else {
      await _seekSafely(readPlayer(), target);
    }
    // Check before resuming: an old seek must not resume a new drag or file.
    if (!_current(session)) {
      if (_alive && session == _session) _clearOwnedPreview();
      return;
    }
    if (resume) {
      try {
        await readPlayer().play();
      } catch (_) {}
    }
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (_alive && session == _session) _clearOwnedPreview();
  }

  void dispose() {
    _alive = false;
    _session++;
    _settleTimer?.cancel();
    _settleTimer = null;
    // end() already cleared _active, but its pending preview still belongs here.
    _clearOwnedPreview();
    _active = false;
    _resume = false;
    _pending = null;
    _lastFlushed = null;
  }
}
