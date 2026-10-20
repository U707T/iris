import 'package:flutter_test/flutter_test.dart';
import 'package:iris/utils/throttled_seek.dart';

void main() {
  late DateTime now;
  late List<Duration> sent;

  ThrottledSeek build() => ThrottledSeek(
        seekTo: sent.add,
        interval: const Duration(milliseconds: 120),
        clock: () => now,
      );

  setUp(() {
    now = DateTime(2026, 1, 1, 12);
    sent = [];
  });

  test('第一次立即发送, 间隔内只保留最后一次, 松手补发', () {
    final throttle = build()..begin();

    throttle.seek(const Duration(seconds: 1));
    expect(sent, [const Duration(seconds: 1)]);

    now = now.add(const Duration(milliseconds: 40));
    throttle.seek(const Duration(seconds: 2));
    throttle.seek(const Duration(seconds: 3));
    expect(sent, [const Duration(seconds: 1)], reason: '节流期内不应发送');

    now = now.add(const Duration(milliseconds: 120));
    throttle.seek(const Duration(seconds: 4));
    expect(sent, [const Duration(seconds: 1), const Duration(seconds: 4)]);

    throttle.seek(const Duration(seconds: 5));
    throttle.end();
    expect(sent.last, const Duration(seconds: 5));
  });

  test('没有 begin 时忽略 seek, end 也不会发', () {
    final throttle = build();
    throttle.seek(const Duration(seconds: 1));
    throttle.end();
    expect(sent, isEmpty);
  });

  test('end 之后不再发送', () {
    final throttle = build()..begin();
    throttle.seek(const Duration(seconds: 1));
    throttle.end();
    sent.clear();

    throttle.seek(const Duration(seconds: 2));
    throttle.end();
    expect(sent, isEmpty);
  });
}
