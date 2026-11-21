import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// Queue entries, including repeated files, each own a load lifetime.
void usePlaybackEntryEffect({
  required Object? file,
  required int entryIndex,
  required VoidCallback load,
  required VoidCallback stop,
  required VoidCallback invalidate,
}) {
  useEffect(() {
    var alive = true;
    // Keyed hooks initialize their replacement before disposing the old effect
    // at the end of build. Let that cleanup invalidate the old session first.
    scheduleMicrotask(() {
      if (!alive) return;
      if (file == null) {
        invalidate();
        stop();
      } else {
        load();
      }
    });
    return () {
      alive = false;
      invalidate();
    };
  }, [file, entryIndex]);
}

/// Owns one media load and its late backend errors. Native operations can finish
/// after cancellation; only the current generation may publish state or play.
class PlaybackLoadSession extends ChangeNotifier {
  int _generation = 0;
  bool _alive = true;
  StreamSubscription<String>? _errors;
  bool initializing = false;
  String? error;

  /// Identity of the last successfully loaded entry; invalidation clears it.
  Object? loadedIdentity;

  void invalidate() {
    _generation++;
    final subscription = _errors;
    _errors = null;
    if (subscription != null) unawaited(subscription.cancel());
    initializing = false;
    error = null;
    loadedIdentity = null;
  }

  Future<void> load({
    Object? identity,
    required Stream<String> errors,
    required Future<void> Function() ready,
    required Future<void> Function() open,
    required Future<void> Function() firstFrame,
    required Future<void> Function() play,
    required bool Function() shouldPlay,
  }) async {
    if (!_alive) return;
    invalidate();
    final generation = _generation;
    bool current() => _alive && generation == _generation;
    initializing = true;
    error = null;
    notifyListeners();
    try {
      await ready();
      if (!current()) return;
      _errors = errors.listen((message) {
        if (!current()) return;
        error = message;
        initializing = false;
        // A failed load must not resume after its first-frame wait completes.
        _generation++;
        notifyListeners();
      });
      if (!current()) return;
      await open();
      if (!current()) return;
      await firstFrame();
      if (!current()) return;
      if (shouldPlay()) await play();
    } catch (e) {
      if (current()) error = e.toString();
    } finally {
      if (current()) {
        loadedIdentity = error == null ? identity : null;
        initializing = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _alive = false;
    invalidate();
    super.dispose();
  }
}
