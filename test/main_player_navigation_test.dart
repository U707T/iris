import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/store/play_queue_state.dart';
import 'package:iris/store/persistence/json_persistence.dart';
import 'package:iris/store/persistence/key_value_store.dart';
import 'package:iris/store/use_play_queue_store.dart';

class _MemoryStore implements KeyValueStore {
  String? value;
  @override
  Future<String?> read(String key) async => value;
  @override
  Future<void> write(String key, String value) async => this.value = value;
  @override
  Future<void> delete(String key) async => value = null;
}

void main() {
  test(
    'previous and next follow queue order, wrap and retain repeated entries',
    () async {
      final store = PlayQueueStore(
        persistence: JsonPersistence<PlayQueueState>(
          store: _MemoryStore(),
          key: 'queue',
          fromJson: PlayQueueState.fromJson,
          toJson: (state) => state.toJson(),
        ),
      );
      await store.ready;
      const a = FileItem(name: 'a.mp4', uri: '/a.mp4');
      const b = FileItem(name: 'b.mp4', uri: '/b.mp4');
      await store.update(
        playQueue: [
          const PlayQueueItem(file: a, index: 94),
          const PlayQueueItem(file: b, index: 11),
          const PlayQueueItem(file: a, index: 37),
        ],
        index: 94,
      );
      await store.next();
      expect(store.state.currentIndex, 11);
      await store.previous();
      expect(store.state.currentIndex, 94);
      await store.previous();
      expect(store.state.currentIndex, 37);
      await store.next();
      expect(store.state.currentIndex, 94);
      await store.updateCurrentIndex(-1);
      await store.next();
      expect(store.state.currentIndex, 94);
      await store.updateCurrentIndex(-1);
      await store.previous();
      expect(store.state.currentIndex, 37);
      await store.update(playQueue: [], index: -1);
      await store.next();
      await store.previous();
      expect(store.state.currentIndex, -1);
      await store.dispose();
    },
  );
}
