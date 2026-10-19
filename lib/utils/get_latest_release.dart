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
/// 启动时的检查不应拖慢或打断播放。
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
    final response = await http
        .get(Uri.parse(api))
        .timeout(const Duration(seconds: 10));

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

    final String version = data['tag_name'] ?? 'Unknown version';
    final String url =
        data['html_url'] ?? 'https://github.com/U707T/iris/releases/';
    final String? downloadUrl = asset['browser_download_url']?.toString();
    final int size = int.tryParse('${asset['size']}') ?? 0;
    final String changeLog = data['body']?.toString() ?? '';

    if (downloadUrl == null || downloadUrl.isEmpty) {
      logger('Release asset has no download url');
      return null;
    }

    final bool isUpdate = isVersionUpdated(packageInfo.version, version);

    if (!isUpdate) return null;

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

/// 解析版本号: 允许 `v` 前缀与 `-rc.1` 这类后缀, 无法解析的部分按 0 处理。
/// (旧实现直接 int.parse, 遇到 `v2.3.0-rc.1` 会抛 FormatException)
List<int> _parseVersion(String version) => version
    .replaceFirst(RegExp(r'^[vV]'), '')
    .split('.')
    .map((part) => int.tryParse(RegExp(r'^\d+').stringMatch(part) ?? '') ?? 0)
    .toList();

bool isVersionUpdated(String currentVersion, String latestVersion) {
  final current = _parseVersion(currentVersion);
  final latest = _parseVersion(latestVersion);

  for (int i = 0; i < current.length; i++) {
    final int latestPart = i < latest.length ? latest[i] : 0;
    if (current[i] < latestPart) {
      return true;
    } else if (current[i] > latestPart) {
      return false;
    }
  }

  return false;
}
