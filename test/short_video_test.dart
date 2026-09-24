import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/file.dart';
import 'package:iris/utils/short_video.dart';

FileItem _video(String name) =>
    FileItem(name: name, uri: name, type: ContentType.video);

FileItem _audio(String name) =>
    FileItem(name: name, uri: name, type: ContentType.audio);

PlayQueueItem _item(FileItem file, int index) =>
    PlayQueueItem(file: file, index: index);

void main() {
  group('getVideoItems', () {
    test('只保留视频条目', () {
      final queue = [
        _item(_video('a'), 0),
        _item(_audio('b'), 1),
        _item(_video('c'), 2),
      ];
      expect(getVideoItems(queue).map((e) => e.file.name).toList(), ['a', 'c']);
    });

    test('全为音频时返回空列表', () {
      final queue = [_item(_audio('a'), 0), _item(_audio('b'), 1)];
      expect(getVideoItems(queue), isEmpty);
    });
  });

  group('pickShortVideoIndex', () {
    final items = [
      _item(_video('v0'), 0),
      _item(_video('v1'), 1),
      _item(_video('v3'), 3),
      _item(_video('v4'), 4),
    ];

    test('当前项是视频时取原下标', () {
      expect(pickShortVideoIndex(items, 3), 2);
      expect(pickShortVideoIndex(items, 0), 0);
    });

    test('当前项是音频时取其后的第一条视频', () {
      expect(pickShortVideoIndex(items, 2), 2);
      expect(pickShortVideoIndex(items, -1), 0);
    });

    test('其后没有视频时取最后一条', () {
      expect(pickShortVideoIndex(items, 5), 3);
      expect(pickShortVideoIndex(items, 4), 3);
    });

    test('空列表返回 -1', () {
      expect(pickShortVideoIndex(const [], 0), -1);
    });
  });
}
