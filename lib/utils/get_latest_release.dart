import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:iris/utils/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';

class Release {
  final String version;
  final String url;
  final String downloadUrl;
  final int size;
  final String changeLog;

  Release({
    required this.version,
    required this.url,
    required this.downloadUrl,
    required this.size,
    required this.changeLog,
  });
}

/// 检查 GitHub 上的最新版本。
///
/// 网络不可用 / 超时 / 返回结构异常都只返回 null, 不向界面抛异常:
/// 检查更新不应拖慢或打断播放。
Future<Release?> getLatestRelease() async {
  String platform = '';

  if (Platform.isWindows) {
    platform = 'windows';
  } else if (Platform.isAndroid) {
    platform = 'android';
  } else {
    logger('Unsupported platform');
    return null;
  }

  try {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    if (packageInfo.version.isEmpty) return null;

    const api = 'https://api.github.com/repos/U707T/iris/releases/latest';

    // 没有超时的请求在网络异常时会一直挂着 (界面永远停在"检查更新")
    final response =
        await http.get(Uri.parse(api)).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      logger('Failed to load latest release: ${response.statusCode}');
      return null;
    }

    final data = json.decode(response.body);
    if (data is! Map) {
      logger('Unexpected release payload');
      return null;
    }

    final assets = data['assets'];
    if (assets is! List) {
      logger('No assets in latest release');
      return null;
    }

    // 以前直接 `filtteredAssets.first`: 发布里没有对应平台附件时抛
    // StateError (被 catch 吞掉, 表现和"检查失败"一样, 但日志里是异常)
    final matchedAssets = assets
        .whereType<Map>()
        .where((asset) =>
            (asset['name'] ?? '').toString().toLowerCase().contains(platform))
        .toList();

    if (matchedAssets.isEmpty) {
      logger('No $platform asset in latest release');
      return null;
    }

    final asset = matchedAssets.first;
    final String version = data['tag_name']?.toString() ?? 'Unknown version';
    final String url = data['html_url']?.toString() ??
        'https://github.com/U707T/iris/releases/';
    final String? downloadUrl = asset['browser_download_url']?.toString();
    final int size = int.tryParse('${asset['size']}') ?? 0;
    final String changeLog = data['body']?.toString() ?? '';

    if (downloadUrl == null || downloadUrl.isEmpty) {
      logger('Release asset has no download url');
      return null;
    }

    if (!isVersionUpdated(packageInfo.version, version)) return null;

    return Release(
      version: version,
      url: url,
      downloadUrl: downloadUrl,
      size: size,
      changeLog: changeLog,
    );
  } on TimeoutException {
    logger('Timeout fetching latest release');
    return null;
  } catch (e) {
    logger('Error fetching latest release: $e');
    return null;
  }
}

/// 解析后的版本号: 数字段 + 是否为预发布 (`-rc.1` 这类后缀)。
class _ParsedVersion {
  const _ParsedVersion(this.parts, {required this.isPrerelease});

  final List<int> parts;
  final bool isPrerelease;

  int partAt(int index) => index < parts.length ? parts[index] : 0;
}

/// 解析版本号: 允许 `v` 前缀、`-rc.1` 这类预发布后缀与 `+25` 构建号,
/// 无法解析的部分按 0 处理。
/// (旧实现直接 int.parse, 遇到 `v2.3.0-rc.1` 会抛 FormatException)
_ParsedVersion _parseVersion(String version) {
  var rest = version.trim().replaceFirst(RegExp(r'^[vV]'), '');
  final int suffixIndex = rest.indexOf(RegExp(r'[-+]'));
  final bool isPrerelease = suffixIndex >= 0 && rest[suffixIndex] == '-';
  if (suffixIndex >= 0) rest = rest.substring(0, suffixIndex);

  return _ParsedVersion(
    rest
        .split('.')
        .map((part) => int.tryParse(RegExp(r'^\d+').stringMatch(part) ?? '') ?? 0)
        .toList(),
    isPrerelease: isPrerelease,
  );
}

/// [latestVersion] 是否比 [currentVersion] 新。
///
/// 按数字段逐段比较 (缺失的段按 0 处理, 因此 `2.3` 与 `2.3.0` 相同);
/// 数字段完全相同时 `2.3.0-rc.1` 比 `2.3.0` 旧 (预发布不算正式版)。
/// 任一侧无法解析都不抛异常。
bool isVersionUpdated(String currentVersion, String latestVersion) {
  final current = _parseVersion(currentVersion);
  final latest = _parseVersion(latestVersion);

  final int length = current.parts.length > latest.parts.length
      ? current.parts.length
      : latest.parts.length;

  for (int i = 0; i < length; i++) {
    final int currentPart = current.partAt(i);
    final int latestPart = latest.partAt(i);
    if (currentPart < latestPart) return true;
    if (currentPart > latestPart) return false;
  }

  // 数字段一致: 只有「自己是预发布、对方是正式版」才算有新版
  return current.isPrerelease && !latest.isPrerelease;
}
