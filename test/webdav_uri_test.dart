import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/models/storages/webdav.dart';

WebDAVStorage _storage(List<String> basePath, {bool https = false}) =>
    WebDAVStorage(
      id: 'dav',
      name: 'Dav',
      host: 'nas.local',
      basePath: basePath,
      port: '5244',
      username: 'admin',
      password: 'secret',
      https: https,
    );

void main() {
  group('buildWebDAVFileUri', () {
    test('默认 /dav 路径', () {
      expect(
        buildWebDAVFileUri(
          storage: _storage(['/dav']),
          path: ['/dav'],
          fileName: 'movie.mp4',
        ),
        'http://nas.local:5244/dav/movie.mp4',
      );
    });

    test('子目录不会被合并成一段', () {
      expect(
        buildWebDAVFileUri(
          storage: _storage(['/dav/movies']),
          path: ['/dav/movies'],
          fileName: 'movie.mp4',
        ),
        'http://nas.local:5244/dav/movies/movie.mp4',
      );
    });

    test('多段 basePath 与逐级进入的路径', () {
      expect(
        buildWebDAVFileUri(
          storage: _storage(['dav', 'movies']),
          path: ['dav', 'movies', '2024'],
          fileName: 'movie.mp4',
        ),
        'http://nas.local:5244/dav/movies/2024/movie.mp4',
      );
    });

    test('文件名里的空格 / # / ? / % 被正确编码', () {
      expect(
        buildWebDAVFileUri(
          storage: _storage(['/dav']),
          path: ['/dav'],
          fileName: 'a #1? 100%.mp4',
        ),
        'http://nas.local:5244/dav/a%20%231%3F%20100%25.mp4',
      );
    });

    test('https 与空端口', () {
      final storage = WebDAVStorage(
        id: 'dav',
        name: 'Dav',
        host: 'nas.local',
        basePath: const ['/dav'],
        port: '',
        username: 'admin',
        password: 'secret',
        https: true,
      );
      expect(
        buildWebDAVFileUri(
          storage: storage,
          path: storage.basePath,
          fileName: 'movie.mp4',
        ),
        'https://nas.local/dav/movie.mp4',
      );
    });
  });
}
