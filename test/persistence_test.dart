import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/store/persistence/json_persistence.dart';
import 'package:iris/store/persistence/key_value_store.dart';
import 'package:iris/store/persistent_store.dart';

class _MemoryStore implements KeyValueStore {
  final Map<String, String> values = {};
  int writes = 0;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    writes++;
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _FailingReadStore extends _MemoryStore {
  @override
  Future<String?> read(String key) async {
    throw const FormatException('boom');
  }
}

class _SlowStore extends _MemoryStore {
  final Completer<void> firstWriteGate = Completer<void>();

  @override
  Future<void> write(String key, String value) async {
    writes++;
    if (writes == 1) {
      await firstWriteGate.future;
    }
    values[key] = value;
  }
}

JsonPersistence<Map<String, dynamic>> _persistence(
  KeyValueStore store, {
  KeyValueStore? legacy,
  String? legacyKey,
}) =>
    JsonPersistence<Map<String, dynamic>>(
      store: store,
      key: 'test',
      legacyStore: legacy,
      legacyKey: legacyKey,
      fromJson: (json) => json,
      toJson: (value) => value,
    );

class _TestStore extends PersistentStore<Map<String, dynamic>> {
  _TestStore(JsonPersistence<Map<String, dynamic>> persistence)
      : super(const {}, persistence);

  @override
  Future<Map<String, dynamic>?> load() => loadPersisted();
}

void main() {
  group('JsonPersistence', () {
    test('写入带 schema 的数据并能读回', () async {
      final store = _MemoryStore();
      final persistence = _persistence(store);

      await persistence.save({'x': 1});
      final raw = jsonDecode(store.values['test']!) as Map<String, dynamic>;
      expect(raw['schema'], 1);
      expect(raw['data'], {'x': 1});

      expect(await persistence.load(), {'x': 1});
    });

    test('没有 schema 的旧裸 JSON 按 v1 读取', () async {
      final store = _MemoryStore()..values['test'] = '{"x":2}';
      expect(await _persistence(store).load(), {'x': 2});
    });

    test('从旧后端迁移：先写新后端，再删旧 key', () async {
      final store = _MemoryStore();
      final legacy = _MemoryStore()..values['old'] = '{"x":3}';

      final loaded = await _persistence(
        store,
        legacy: legacy,
        legacyKey: 'old',
      ).load();

      expect(loaded, {'x': 3});
      expect(store.values['test'], contains('"schema":1'));
      expect(legacy.values.containsKey('old'), isFalse);
    });

    test('未来版本拒绝读取', () async {
      final store = _MemoryStore()
        ..values['test'] = '{"schema":99,"data":{"x":1}}';

      await expectLater(
        _persistence(store).load(),
        throwsA(isA<StateError>()),
      );
    });

    test('旧 schema 会走迁移链', () async {
      final store = _MemoryStore()
        ..values['test'] = '{"schema":1,"data":{"x":1}}';
      final persistence = JsonPersistence<Map<String, dynamic>>(
        store: store,
        key: 'test',
        schemaVersion: 2,
        migrations: {
          1: (data) => {...data, 'migrated': true},
        },
        fromJson: (json) => json,
        toJson: (value) => value,
      );

      expect(
        await persistence.load(),
        {'x': 1, 'migrated': true},
      );
    });

    test('读取失败会抛出，不会被当成"没有数据"', () async {
      await expectLater(
        _persistence(_FailingReadStore()).load(),
        throwsA(isA<FormatException>()),
      );
    });

    test('并发保存只保留最新快照，且写入串行', () async {
      final store = _SlowStore();
      final persistence = _persistence(store);

      final first = persistence.save({'v': 1});
      await Future<void>.delayed(Duration.zero);
      final second = persistence.save({'v': 2});
      final third = persistence.save({'v': 3});

      store.firstWriteGate.complete();
      await Future.wait([first, second, third]);

      final raw = jsonDecode(store.values['test']!) as Map<String, dynamic>;
      expect((raw['data'] as Map)['v'], 3);
      expect(store.writes, 2);
    });
  });

  test('FileKeyValueStore 原子覆盖并删除', () async {
    final directory = await Directory.systemTemp.createTemp('iris_store_');
    addTearDown(() => directory.delete(recursive: true));

    final store = FileKeyValueStore(directoryProvider: () async => directory);
    expect(await store.read('k'), isNull);

    await store.write('k', 'first');
    await store.write('k', 'second');
    expect(await store.read('k'), 'second');
    expect(await File('${directory.path}/k.json').exists(), isTrue);

    await store.delete('k');
    expect(await store.read('k'), isNull);
  });

  test('加载失败后拒绝覆盖写入', () async {
    final store = _FailingReadStore();
    final persistence = _persistence(store);
    final subject = _TestStore(persistence);

    await subject.ready;
    expect(subject.loadError, isNotNull);

    await subject.save({'x': 1});
    expect(store.writes, 0);
  });
}
