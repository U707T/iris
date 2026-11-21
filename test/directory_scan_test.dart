import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/storages/directory_scan.dart';
import 'package:iris/models/storages/local.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/utils/search_files.dart';

class _Stat extends Fake implements FileStat {
  @override
  DateTime get modified => DateTime.utc(2026);

  @override
  int get size => 10;
}

class _File extends Fake implements File {
  _File(this.path, this.readStat);

  @override
  final String path;
  final Future<FileStat> Function() readStat;
  int calls = 0;

  @override
  Future<FileStat> stat() {
    calls++;
    return readStat();
  }
}

class _Directory extends Fake implements Directory {
  @override
  String get path => 'photos.jpg';

  @override
  Future<FileStat> stat() async => _Stat();
}

final _local = LocalStorage(
  type: StorageType.internal,
  name: 'Local',
  basePath: const ['local'],
);

const _wait = Duration(seconds: 3);

String _davEntry(String path) =>
    '''
<d:response>
  <d:href>$path</d:href>
  <d:propstat>
    <d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop>
    <d:status>HTTP/1.1 200 OK</d:status>
  </d:propstat>
</d:response>
''';

void main() {
  test('媒体浏览在 stat 前过滤，默认列表保留可用作封面的图片', () async {
    final hidden = _File('cover.png', () async => _Stat());
    final video = _File('film.MP4', () async => _Stat());
    final audio = _File('song.flac', () async => _Stat());
    final entries = <FileSystemEntity>[hidden, video, audio, _Directory()];

    final media = await scanLocalDirectoryEntries(
      _local,
      _local.basePath,
      Stream.fromIterable(entries),
      mediaOnly: true,
    );
    expect(media.map((item) => item.name), [
      'film.MP4',
      'song.flac',
      'photos.jpg',
    ]);
    expect(media.last.isDir, isTrue);
    expect(video.calls + audio.calls, 2);
    expect(hidden.calls, 0);

    final all = await scanLocalDirectoryEntries(
      _local,
      _local.basePath,
      Stream.fromIterable(entries),
    );
    expect(all.first.name, 'cover.png');
    expect(hidden.calls, 1);
  });

  test('取消关闭正在等待目录条目的枚举', () async {
    final scan = DirectoryScan();
    final started = Completer<void>();
    final released = Completer<void>();
    final entries = StreamController<FileSystemEntity>(
      onListen: started.complete,
      onCancel: released.complete,
    );
    addTearDown(entries.close);

    final result = scanLocalDirectoryEntries(
      _local,
      _local.basePath,
      entries.stream,
      scan: scan,
    );
    await started.future.timeout(_wait);
    scan.cancel();
    await released.future.timeout(_wait);
    expect(await result.timeout(_wait), isEmpty);
  });

  test('取消正在读取的 stat 批次后不会开始下一批', () async {
    final scan = DirectoryScan();
    final batchStarted = Completer<void>();
    final finishStat = Completer<FileStat>();
    var inFlight = 0;
    final files = List.generate(
      40,
      (index) => _File('$index.mp4', () {
        if (++inFlight == 16) batchStarted.complete();
        return finishStat.future;
      }),
    );
    final result = scanLocalDirectoryEntries(
      _local,
      _local.basePath,
      Stream.fromIterable(files),
      scan: scan,
    );
    await batchStarted.future.timeout(_wait);
    scan.cancel();
    finishStat.complete(_Stat());
    expect(await result.timeout(_wait), isEmpty);
    expect(inFlight, 16);
  });

  test('取消 WebDAV 搜索结束正在等待的请求并跳过其它子目录', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final childRequested = Completer<void>();
    final requests = <String>[];
    server.listen((request) {
      final path = request.uri.path;
      requests.add(path);
      if (path == '/dav/' || path == '/dav') {
        request.response
          ..statusCode = 207
          ..headers.contentType = ContentType('application', 'xml')
          ..write('''<d:multistatus xmlns:d="DAV:">
${_davEntry('/dav/')}${_davEntry('/dav/waiting/')}${_davEntry('/dav/other/')}
</d:multistatus>''');
        unawaited(request.response.close());
      } else if (path.contains('/waiting')) {
        // Leave the response pending to require active transport cancellation.
        childRequested.complete();
      } else {
        request.response.statusCode = 404;
        unawaited(request.response.close());
      }
    });

    final storage = WebDAVStorage(
      id: 'dav',
      name: 'Dav',
      host: '127.0.0.1',
      basePath: const ['/dav'],
      port: '${server.port}',
      username: '',
      password: '',
      https: false,
    );
    final scan = DirectoryScan();
    final result = searchFiles(
      storage: storage,
      basePath: storage.basePath,
      query: 'film',
      scan: scan,
    );

    await childRequested.future.timeout(_wait);
    scan.cancel();
    expect(await result.timeout(_wait), isEmpty);
    expect(requests, hasLength(2));
  });
}
