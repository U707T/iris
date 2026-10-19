import 'package:flutter_test/flutter_test.dart';
import 'package:iris/utils/get_latest_release.dart';

/// 版本比较: 更新检查里的 tag 可能带 `v` 前缀 / `-rc.1` 后缀,
/// 旧实现直接 int.parse 会抛 FormatException。
void main() {
  test('常规版本比较', () {
    expect(isVersionUpdated('2.3.0', 'v2.3.1'), isTrue);
    expect(isVersionUpdated('2.3.0', 'v2.3.0'), isFalse);
    expect(isVersionUpdated('2.9.9', 'v3.0.0'), isTrue);
    expect(isVersionUpdated('2.10.0', 'v2.9.9'), isFalse);
    expect(isVersionUpdated('2.3', 'v2.3.0'), isFalse);
  });

  test('RC / 非数字后缀不崩溃', () {
    expect(isVersionUpdated('2.3.0', 'v2.3.0-rc.1'), isFalse);
    expect(isVersionUpdated('2.3.0-rc.1', 'v2.3.0'), isFalse);
    expect(isVersionUpdated('2.3.0-rc.1', 'v2.3.1'), isTrue);
    expect(isVersionUpdated('2.3.0', 'garbage'), isFalse);
  });
}
