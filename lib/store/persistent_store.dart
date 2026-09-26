import 'package:material_ui/material_ui.dart';
import 'package:flutter_zustand/flutter_zustand.dart';

abstract class PersistentStore<T> extends Store<T> {
  PersistentStore(super.initialState) {
    _init();
  }

  bool _isLoaded = false;

  /// Whether the persisted state has been loaded from storage.
  bool get isLoaded => _isLoaded;

  Future<void> _init() async {
    try {
      final loaded = await load();
      if (loaded != null) {
        set(loaded);
      }
    } finally {
      _isLoaded = true;
    }
  }

  Future<T?> load();

  Future<void> save(T state);

  @override
  @mustCallSuper
  Future<void> dispose() async {
    await save(state);
    await super.dispose();
  }
}
