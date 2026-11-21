/// Owns one directory listing or a sequence of listings from a search.
final class DirectoryScan {
  bool _isCancelled = false;
  final _abortCallbacks = <void Function()>{};

  bool get isCancelled => _isCancelled;

  /// Registers an abort callback for an in-flight operation. The returned
  /// function removes it when that operation settles.
  void Function() onCancel(void Function() abort) {
    if (_isCancelled) {
      abort();
      return () {};
    }
    _abortCallbacks.add(abort);
    return () => _abortCallbacks.remove(abort);
  }

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    final callbacks = _abortCallbacks.toList();
    _abortCallbacks.clear();
    for (final abort in callbacks) {
      abort();
    }
  }
}
