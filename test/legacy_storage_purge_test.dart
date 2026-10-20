import 'package:flutter_test/flutter_test.dart';
import 'package:iris/utils/purge_legacy_storage_types.dart';

/// 移除 FTP 后, 旧版本写下的队列 / 历史里可能还有 `storageType: ftp`:
/// 直接 fromJson 会抛异常并丢掉整份状态, 所以先清洗掉这些条目。

Map<String, dynamic> _item(String uri, String type, int index) => {
      'file': {'name': uri, 'uri': uri, 'storageType': type},
      'index': index,
    };

void main() {
  group('sanitizePlayQueueJson', () {
    test('没有 ftp 条目时原样返回', () {
      final data = {
        'playQueue': [_item('a', 'internal', 0)],
        'currentIndex': 0,
      };
      expect(sanitizePlayQueueJson(data), same(data));
    });

    test('剔除 ftp 条目, 保留其余', () {
      final data = {
        'playQueue': [
          _item('a', 'internal', 0),
          _item('b', 'ftp', 1),
          _item('c', 'webdav', 2),
        ],
        'currentIndex': 0,
      };
      final out = sanitizePlayQueueJson(data)!;
      expect((out['playQueue'] as List).length, 2);
      expect((out['playQueue'] as List).any((e) => e['index'] == 1), isFalse);
      expect(out['currentIndex'], 0);
    });

    test('当前项被剔除时落到第一条', () {
      final data = {
        'playQueue': [_item('b', 'ftp', 0), _item('c', 'webdav', 1)],
        'currentIndex': 0,
      };
      final out = sanitizePlayQueueJson(data)!;
      expect(out['currentIndex'], 1);
    });

    test('全是 ftp 条目时返回 null', () {
      final data = {
        'playQueue': [_item('b', 'ftp', 0)],
        'currentIndex': 0,
      };
      expect(sanitizePlayQueueJson(data), isNull);
    });
  });

  group('sanitizeHistoryJson', () {
    test('剔除 ftp 历史, 保留其余', () {
      final data = {
        'history': {
          'x:a': {'file': {'name': 'a', 'uri': 'a', 'storageType': 'internal'}},
          'y:b': {'file': {'name': 'b', 'uri': 'b', 'storageType': 'ftp'}},
        },
      };
      final out = sanitizeHistoryJson(data)!;
      expect((out['history'] as Map).keys, ['x:a']);
    });

    test('没有 ftp 时原样返回', () {
      final data = {
        'history': {
          'x:a': {'file': {'name': 'a', 'uri': 'a', 'storageType': 'internal'}},
        },
      };
      expect(sanitizeHistoryJson(data), same(data));
    });
  });
}
