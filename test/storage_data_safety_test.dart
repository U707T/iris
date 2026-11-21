import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/models/storages/webdav.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/models/store/play_queue_state.dart';
import 'package:iris/models/store/storage_state.dart';
import 'package:iris/store/persistence/json_persistence.dart';
import 'package:iris/store/persistence/key_value_store.dart';
import 'package:iris/store/state_decoders.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/store/use_storage_store.dart';
import 'package:iris/utils/data_migration.dart';
import 'package:iris/utils/refresh_play_queue.dart';

class _DelayedStore implements KeyValueStore {
  final readGate = Completer<String?>();
  final writeGate = Completer<void>();
  String? saved;
  bool failWrites = false;
  bool delayWrites = false;
  int writes = 0;

  @override
  Future<String?> read(String key) => readGate.future;
  @override
  Future<void> write(String key, String value) async {
    writes++;
    if (delayWrites) await writeGate.future;
    if (failWrites) throw const FileSystemException('disk full');
    saved = value;
  }

  @override
  Future<void> delete(String key) async {}
}

WebDAVStorage _dav({
  String host = 'nas.local',
  String port = '443',
  bool https = true,
  String password = ' secret ',
}) => WebDAVStorage(
  id: 'dav',
  name: 'Dav',
  host: host,
  port: port,
  basePath: const ['/dav'],
  username: 'user',
  password: password,
  https: https,
);

FileItem _file(String folder, String name, {String storage = 'local'}) =>
    FileItem(
      storageId: storage,
      name: name,
      uri: '$folder/$name',
      path: [folder, name],
    );

void main() {
  group('WebDAV authorization origin', () {
    test('exact origin, case normalization and effective default port', () {
      final dav = _dav(port: '');
      final auth = dav.getAuthForUri('https://NAS.LOCAL:443/dav/movie.mp4');
      expect(auth, 'Basic ${base64Encode(utf8.encode('user: secret '))}');
      expect(
        _dav(port: '8443')
            .getAuthForUri('https://nas.local:8443/dav/movie.mp4'),
        auth,
      );
    });
    test('edited connection never sends new credentials to old URL', () {
      final oldUrl = buildWebDAVFileUri(
        storage: _dav(),
        path: const ['/dav'],
        fileName: 'a.mp4',
      );
      final changed = _dav(host: 'new.local', password: 'new secret');
      expect(() => changed.getAuthForUri(oldUrl), throwsStateError);
    });
    test('scheme, port, userinfo and relative URL fail closed', () {
      final dav = _dav();
      for (final uri in [
        'http://nas.local/dav/a.mp4',
        'https://nas.local:444/dav/a.mp4',
        'https://user@nas.local/dav/a.mp4',
        '/dav/a.mp4',
        'https://nas.local.evil/dav/a.mp4',
      ]) {
        expect(() => dav.getAuthForUri(uri), throwsStateError, reason: uri);
      }
      expect(
        () =>
            _dav(port: 'invalid').getAuthForUri('https://nas.local/dav/a.mp4'),
        throwsStateError,
      );
    });
  });

  group('delayed persistent loads', () {
    test(
      'settings mutation waits and preserves unrelated loaded fields',
      () async {
        final backend = _DelayedStore();
        final store = AppStore(
          persistence: JsonPersistence<AppState>(
            store: backend,
            key: 'app',
            fromJson: AppState.fromJson,
            toJson: (s) => s.toJson(),
          ),
        );
        final changed = store.updateVolume(25);
        final toggled = store.toggleRepeat();
        await Future<void>.delayed(Duration.zero);
        expect(backend.writes, 0);
        backend.readGate.complete(
          jsonEncode(
            AppState(
              volume: 90,
              language: 'zh',
              repeat: Repeat.one,
              shuffle: true,
            ).toJson(),
          ),
        );
        await Future.wait([changed, toggled]);
        await store.flush();
        expect(store.state.volume, 25);
        expect(store.state.language, 'zh');
        expect(store.state.shuffle, true);
        expect(store.state.repeat, Repeat.all);
        expect((jsonDecode(backend.saved!)['data'] as Map)['language'], 'zh');
      },
    );
    test('queue append waits rather than replacing the loaded queue', () async {
      final backend = _DelayedStore();
      final store = PlayQueueStore(
        persistence: JsonPersistence<PlayQueueState>(
          store: backend,
          key: 'queue',
          fromJson: decodePlayQueueState,
          toJson: (s) => s.toJson(),
        ),
      );
      final added = store.add([_file('/b', 'b.mp4')]);
      backend.readGate.complete(
        jsonEncode(
          PlayQueueState(
            playQueue: [PlayQueueItem(file: _file('/a', 'a.mp4'), index: 7)],
            currentIndex: 7,
          ).toJson(),
        ),
      );
      await added;
      expect(store.state.playQueue.map((i) => i.index), [7, 8]);
      expect(store.state.currentIndex, 7);
    });
    test(
      'connection deletion waits for load and clears related state',
      () async {
        final backend = _DelayedStore();
        final dav = _dav();
        final store = StorageStore(
          persistence: JsonPersistence<StorageState>(
            store: backend,
            key: 'storage',
            fromJson: decodeStorageState,
            toJson: (s) => s.toJson(),
          ),
        );
        final removed = store.removeStorage(dav);
        backend.readGate.complete(
          jsonEncode(
            StorageState(
              storages: [dav],
              currentStorage: dav,
              currentPath: const ['/dav'],
              favorites: [
                Favorite(storageId: 'dav', path: const ['/dav']),
              ],
            ).toJson(),
          ),
        );
        await removed;
        expect(store.state.storages, isEmpty);
        expect(store.state.currentStorage, isNull);
        expect(store.state.currentPath, isEmpty);
        expect(store.state.favorites, isEmpty);
      },
    );
    test(
      'failed initial load refuses writes and explicit flush reports it',
      () async {
        final backend = _DelayedStore();
        final store = AppStore(
          persistence: JsonPersistence<AppState>(
            store: backend,
            key: 'app',
            fromJson: AppState.fromJson,
            toJson: (s) => s.toJson(),
          ),
        );
        final change = store.updateVolume(20);
        backend.readGate.completeError(const FormatException('corrupt state'));
        await change;
        expect(backend.writes, 0);
        expect(store.saveError, isA<FormatException>());
        await expectLater(store.flush(), throwsA(isA<FormatException>()));
      },
    );
    test(
      'flush waits for physical write and reports failures, then recovers',
      () async {
        final backend = _DelayedStore()..delayWrites = true;
        backend.readGate.complete(null);
        final persistence = JsonPersistence<Map<String, dynamic>>(
          store: backend,
          key: 's',
          fromJson: (s) => s,
          toJson: (s) => s,
        );
        final save = persistence.save({'x': 1});
        var finished = false;
        final flushed = persistence.flush().then((_) => finished = true);
        await Future<void>.delayed(Duration.zero);
        expect(finished, false);
        backend.writeGate.complete();
        await Future.wait([save, flushed]);
        backend.failWrites = true;
        await persistence.save({'x': 2});
        expect(persistence.lastSaveError, isA<FileSystemException>());
        await expectLater(
          persistence.flush(),
          throwsA(isA<FileSystemException>()),
        );
        backend.failWrites = false;
        await persistence.save({'x': 3});
        await persistence.flush();
        expect(persistence.lastSaveError, isNull);
      },
    );
  });

  test(
    'an older successful write does not hide a newer encoding failure',
    () async {
      final backend = _DelayedStore()..delayWrites = true;
      final persistence = JsonPersistence<Map<String, dynamic>>(
        store: backend,
        key: 's',
        fromJson: (s) => s,
        toJson: (s) => s,
      );
      final first = persistence.save({'x': 1});
      await persistence.save({'bad': Object()});
      expect(persistence.lastSaveError, isA<JsonUnsupportedObjectError>());
      backend.writeGate.complete();
      await first;
      await expectLater(
        persistence.flush(),
        throwsA(isA<JsonUnsupportedObjectError>()),
      );
    },
  );

  group('file replacement recovery', () {
    test('both renames fail without destroying the old state', () async {
      final dir = await Directory.systemTemp.createTemp('iris_rename_');
      addTearDown(() => dir.delete(recursive: true));
      final committed = File('${dir.path}/s.json');
      await committed.writeAsString('old');
      var attempts = 0;
      final store = FileKeyValueStore(
        directoryProvider: () async => dir,
        rename: (file, destination) async {
          attempts++;
          throw const FileSystemException('rename blocked');
        },
      );
      await expectLater(
        store.write('s', 'new'),
        throwsA(isA<FileSystemException>()),
      );
      expect(attempts, 2);
      expect(await committed.exists(), false);
      expect(await File('${dir.path}/s.json.bak').readAsString(), 'old');
      expect(await store.read('s'), 'old');
      expect(
        await FileKeyValueStore(directoryProvider: () async => dir).read('s'),
        'old',
        reason: 'a new process can read the last committed value',
      );
    });
    test(
      'restart recovers the backup from a process exit in replacement gap',
      () async {
        final dir = await Directory.systemTemp.createTemp('iris_backup_');
        addTearDown(() async {
          if (!await dir.exists()) return;
          for (var attempt = 0; attempt < 10; attempt++) {
            try {
              await dir.delete(recursive: true);
              return;
            } on FileSystemException {
              if (attempt == 9) rethrow;
              await Future<void>.delayed(const Duration(milliseconds: 50));
            }
          }
        });
        await File('${dir.path}/s.json.bak').writeAsString('old');
        await File('${dir.path}/s.json.tmp').writeAsString('new');
        final store = FileKeyValueStore(directoryProvider: () async => dir);
        expect(await store.read('s'), 'old');
        await store.write('s', 'committed');
        expect(await store.read('s'), 'committed');
        await store.delete('s');
        expect(await store.read('s'), isNull);
      },
    );
  });

  test(
    'migration resumes after failure and never replaces existing new files',
    () async {
      final dir = await Directory.systemTemp.createTemp('iris_migrate_');
      addTearDown(() => dir.delete(recursive: true));
      final old = await Directory('${dir.path}/old').create();
      final target = await Directory('${dir.path}/new').create();
      for (final name in ['flutter_secure_storage.dat', 'a.json', 'b.json']) {
        await File('${old.path}/$name').writeAsString('legacy-$name');
      }
      await File('${target.path}/a.json').writeAsString('new-value');
      var copies = 0;
      await expectLater(
        migrateLegacyDirectory(
          source: old,
          destination: target,
          copyFile: (source, staging) async {
            if (++copies == 2) throw const FileSystemException('interrupted');
            await source.copy(staging.path);
          },
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        await File('${target.path}/$legacyMigrationMarker').exists(),
        false,
      );
      expect(
        await migrateLegacyDirectory(source: old, destination: target),
        true,
      );
      expect(await File('${target.path}/a.json').readAsString(), 'new-value');
      expect(
        await File('${target.path}/b.json').readAsString(),
        'legacy-b.json',
      );
      expect(
        await File('${target.path}/flutter_secure_storage.dat').exists(),
        true,
      );
      expect(
        await migrateLegacyDirectory(source: old, destination: target),
        false,
      );
    },
  );

  test(
    'FTP plus malformed survivor recovers valid entries and preserves stop',
    () {
      final queue = [
        'bad',
        {
          'file': {'name': 'old', 'uri': 'ftp://old', 'storageType': 'ftp'},
          'index': 0,
        },
        {
          'file': {'name': 'good', 'uri': '/good.mp4'},
          'index': 9,
        },
      ];
      final recovered = decodePlayQueueState({
        'playQueue': queue,
        'currentIndex': 0,
      });
      expect(recovered.playQueue.single.index, 9);
      expect(recovered.currentIndex, 9);
      final stopped = decodePlayQueueState({
        'playQueue': queue,
        'currentIndex': -1,
      });
      expect(stopped.currentIndex, -1);
    },
  );

  test(
    'refresh retains other directories, remote links and other connections',
    () {
      final a = _file('/movies', 'a.mp4');
      final deleted = _file('/movies', 'deleted.mp4');
      final outside = _file('/elsewhere', 'b.mp4');
      final remote = FileItem(name: 'stream', uri: 'https://host/stream');
      final otherConnection = _file('/movies', 'c.mp4', storage: 'other');
      final items = [a, deleted, outside, remote, otherConnection];
      final state = PlayQueueState(
        playQueue: [
          for (var i = 0; i < items.length; i++)
            PlayQueueItem(file: items[i], index: i),
        ],
        currentIndex: 2,
      );
      final result = mergeQueueWithListed(
        state: state,
        scannedFrom: a,
        listed: [a, _file('/movies', 'new.mp4')],
      )!;
      expect(result.playQueue.map((i) => i.file.name), [
        'a.mp4',
        'b.mp4',
        'stream',
        'c.mp4',
        'new.mp4',
      ]);
      expect(result.currentIndex, 2);
      expect(identical(result.playQueue[1].file, outside), true);
      expect(identical(result.playQueue[3].file, otherConnection), true);
    },
  );

  test('Windows separator and case variants retain original queue entries', () {
    final a = FileItem(
      name: 'a.mp4',
      uri: 'C:/Movies/a.mp4',
      path: const ['C:/Movies', 'a.mp4'],
    );
    final b = FileItem(
      name: 'b.mp4',
      uri: r'C:\Movies\b.mp4',
      path: const ['C:', 'Movies', 'b.mp4'],
    );
    final state = PlayQueueState(
      playQueue: [
        PlayQueueItem(file: a, index: 0),
        PlayQueueItem(file: b, index: 1),
      ],
      currentIndex: 1,
    );
    final result = mergeQueueWithListed(
      state: state,
      scannedFrom: a,
      listed: [
        a.copyWith(uri: r'c:\movies\a.mp4'),
        b.copyWith(uri: 'c:/movies/b.mp4'),
      ],
    )!;
    expect(result.playQueue.length, 2);
    expect(identical(result.playQueue[0].file, a), true);
    expect(identical(result.playQueue[1].file, b), true);
    expect(result.currentIndex, 1);
  });

  test('refresh never treats missing remote ids as the local connection', () {
    final local = _file('/movies', 'a.mp4', storage: '');
    final orphan = FileItem(
      storageType: StorageType.webdav,
      name: 'remote.mp4',
      uri: 'https://nas/dav/remote.mp4',
      path: const ['/movies', 'remote.mp4'],
    );
    final state = PlayQueueState(
      playQueue: [
        PlayQueueItem(file: local, index: 0),
        PlayQueueItem(file: orphan, index: 1),
      ],
      currentIndex: 0,
    );
    final merged = mergeQueueWithListed(
      state: state,
      scannedFrom: local,
      listed: [local],
    )!;
    expect(merged.playQueue.length, 2);
    expect(identical(merged.playQueue[1].file, orphan), true);
    expect(
      mergeQueueWithListed(
        state: PlayQueueState(
          playQueue: [PlayQueueItem(file: orphan, index: 0)],
        ),
        scannedFrom: orphan,
        listed: [orphan],
      ),
      isNull,
    );
  });

  test('WebDAV keeps URI case and deduplication scoped to its connection', () {
    FileItem remote(String id, String name) => FileItem(
      storageId: id,
      storageType: StorageType.webdav,
      name: name,
      uri: 'https://nas/dav/$name',
      path: ['/dav', name],
    );
    final anchor = remote('a', 'anchor.mp4');
    final oldCase = remote('a', 'Clip.mp4');
    final otherConnection = remote('b', 'clip.mp4');
    final state = PlayQueueState(
      playQueue: [
        PlayQueueItem(file: anchor, index: 0),
        PlayQueueItem(file: oldCase, index: 1),
        PlayQueueItem(file: otherConnection, index: 2),
      ],
      currentIndex: 0,
    );
    final merged = mergeQueueWithListed(
      state: state,
      scannedFrom: anchor,
      listed: [anchor, remote('a', 'clip.mp4')],
    )!;
    expect(merged.playQueue.map((i) => i.file.name), [
      'anchor.mp4',
      'clip.mp4',
      'clip.mp4',
    ]);
    expect(merged.playQueue.map((i) => i.file.storageId), ['a', 'b', 'a']);
    expect(identical(merged.playQueue[1].file, otherConnection), true);
  });

  test('opening folder of deleted WebDAV does not create a local WebDAV', () {
    final file = FileItem(
      storageId: 'gone',
      storageType: StorageType.webdav,
      name: 'a',
      uri: 'https://nas.local/dav/a',
      path: const ['/dav', 'a'],
    );
    expect(storageForFileFolder(file, const [], const []), isNull);
    final known = _dav();
    expect(
      storageForFileFolder(file.copyWith(storageId: 'dav'), [known], const []),
      known,
    );
  });

  test(
    'restored current storage uses canonical credentials and drops orphan',
    () {
      final dav = _dav();
      final edited = _dav(password: 'new-password');
      final state = decodeStorageState({
        'storages': [edited.toJson()],
        'currentStorage': dav.toJson(),
        'currentPath': ['/dav'],
      });
      expect((state.currentStorage as WebDAVStorage).password, 'new-password');
      final orphan = decodeStorageState({
        'storages': [],
        'currentStorage': dav.toJson(),
        'currentPath': ['/dav'],
      });
      expect(orphan.currentStorage, isNull);
    },
  );
}
