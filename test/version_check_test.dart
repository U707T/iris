import 'package:flutter_test/flutter_test.dart';
import 'package:iris/utils/get_latest_release.dart';

/// 版本比较: 更新检查里的 tag 可能带 `v` 前缀 / `-rc.1` 后缀,
/// 旧实现直接 int.parse 会抛 FormatException。
void main() {
  test(
    'portable asset selection ignores installer order and rejects ambiguity',
    () {
      final assets = <dynamic>[
        {'name': 'IRIS-windows-installer.exe', 'size': 10},
        {'name': 'IRIS-windows.zip', 'size': 20},
        {'name': 'IRIS-android-arm64-v8a.apk', 'size': 30},
      ];
      expect(selectReleaseAsset(assets, 'windows')?['size'], 20);
      expect(selectReleaseAsset(assets, 'android')?['size'], 30);
      expect(selectReleaseAsset([assets[1], assets[1]], 'windows'), isNull);
      expect(selectReleaseAsset([], 'windows'), isNull);
      expect(selectReleaseAsset(assets, 'unknown'), isNull);
    },
  );

  test('automatic update binds exact release URL and SHA256', () {
    Release release({String? url, String? digest}) => Release(
      version: 'v2.8.2',
      url: 'https://github.com/U707T/iris/releases/tag/v2.8.2',
      downloadUrl: url ?? 'https://github.com/U707T/iris/releases/download/v2.8.2/IRIS-windows.zip',
      size: 20,
      changeLog: '',
      sha256: digest,
    );
    final digest = 'a' * 64;
    expect(isTrustedPortableUpdate(release(digest: digest)), isTrue);
    expect(isTrustedPortableUpdate(release()), isFalse);
    expect(isTrustedPortableUpdate(release(digest: 'invalid')), isFalse);
    for (final url in [
      'http://github.com/U707T/iris/releases/download/v2.8.2/IRIS-windows.zip',
      'https://example.com/U707T/iris/releases/download/v2.8.2/IRIS-windows.zip',
      'https://github.com/U707T/iris/releases/download/v2.8.3/IRIS-windows.zip',
      'https://github.com/U707T/iris/releases/latest/download/IRIS-windows.zip',
      'https://user@github.com/U707T/iris/releases/download/v2.8.2/IRIS-windows.zip',
      'https://github.com/U707T/iris/releases/download/v2.8.2/IRIS-windows.zip?other=1',
    ]) {
      expect(
        isTrustedPortableUpdate(release(url: url, digest: digest)),
        isFalse,
        reason: url,
      );
    }
  });
  test('常规版本比较', () {
    expect(isVersionUpdated('2.3.0', 'v2.3.1'), isTrue);
    expect(isVersionUpdated('2.3.0', 'v2.3.0'), isFalse);
    expect(isVersionUpdated('2.9.9', 'v3.0.0'), isTrue);
    expect(isVersionUpdated('2.10.0', 'v2.9.9'), isFalse);
    expect(isVersionUpdated('2.3', 'v2.3.0'), isFalse);
    expect(isVersionUpdated('2.3.0', 'v2.3.0.0'), isFalse);
  });

  test('RC / 非数字后缀不崩溃', () {
    // 预发布不算比同号正式版新: 不会给 2.3.0 的用户推 2.3.0-rc.1
    expect(isVersionUpdated('2.3.0', 'v2.3.0-rc.1'), isFalse);
    // 反过来, 自己跑着 rc 时同号正式版才是"有新版" (符合 semver 的先后关系)
    expect(isVersionUpdated('2.3.0-rc.1', 'v2.3.0'), isTrue);
    expect(isVersionUpdated('2.3.0-rc.1', 'v2.3.1'), isTrue);
    expect(isVersionUpdated('2.3.2-rc.1', 'v2.3.1'), isFalse);
    expect(isVersionUpdated('2.3.0', 'garbage'), isFalse);
    expect(isVersionUpdated('', ''), isFalse);
  });
}
