import 'package:flutter_test/flutter_test.dart';
import 'package:iris/store/state_decoders.dart';

void main() {
  group('decodePlayQueueState', () {
    test('坏条目与未知存储类型只丢自己', () {
      final state = decodePlayQueueState({
        'playQueue': [
          {
            'file': {'name': 'a.mp4', 'uri': 'a.mp4'},
            'index': 0,
          },
          {
            'file': {
              'name': 'ftp.mp4',
              'uri': 'ftp://x/a.mp4',
              'storageType': 'ftp',
            },
            'index': 1,
          },
          'not-a-map',
          {
            'file': {'name': 'b.mp4', 'uri': 'b.mp4'},
            'index': 2,
          },
        ],
        'currentIndex': 2,
      });

      expect(state.playQueue.map((e) => e.file.name), ['a.mp4', 'b.mp4']);
      expect(state.currentIndex, 2);
    });

    test('当前项被剔除时落到第一条；-1 停止态保留', () {
      final state = decodePlayQueueState({
        'playQueue': [
          {
            'file': {'name': 'a.mp4', 'uri': 'a.mp4'},
            'index': 5,
          },
        ],
        'currentIndex': 9,
      });
      expect(state.currentIndex, 5);

      final stopped = decodePlayQueueState({
        'playQueue': [
          {
            'file': {'name': 'a.mp4', 'uri': 'a.mp4'},
            'index': 0,
          },
        ],
        'currentIndex': -1,
      });
      expect(stopped.currentIndex, -1);
    });
  });

  test('decodeHistoryState 跳过坏记录', () {
    final state = decodeHistoryState({
      'history': {
        'good': {
          'dateTime': '2024-01-01T00:00:00.000Z',
          'position': 1000000,
          'duration': 2000000,
          'file': {'name': 'a.mp4', 'uri': 'a.mp4'},
        },
        'bad': {
          'dateTime': 'not-a-date',
          'position': 0,
          'duration': 0,
          'file': {'name': 'b.mp4', 'uri': 'b.mp4'},
        },
      },
    });

    expect(state.history.keys, ['good']);
  });

  test('decodeStorageState 跳过坏存储并清理指向它的收藏', () {
    final state = decodeStorageState({
      'storages': [
        {
          'runtimeType': 'local',
          'id': 'ok',
          'type': 'internal',
          'name': 'X',
          'basePath': ['/'],
        },
        {'runtimeType': 'local', 'type': 'ftp', 'name': 'old'},
      ],
      'favorites': [
        {'storageId': 'ok', 'path': ['/', 'a']},
        {'storageId': 'gone', 'path': ['/']},
      ],
      'currentStorage': {'type': 'ftp', 'name': 'old'},
      'currentPath': ['/', 'a'],
    });

    expect(state.storages.map((e) => e.id), ['ok']);
    expect(state.favorites.map((e) => e.storageId), ['ok']);
    expect(state.currentStorage, isNull);
    expect(state.currentPath, ['/', 'a']);
  });
}
