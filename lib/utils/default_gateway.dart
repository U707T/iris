import 'dart:io';

import 'package:flutter/services.dart';

const MethodChannel _networkChannel = MethodChannel('iris/network');

/// 读取本机默认网关地址（路由器 IP），失败返回 null。
///
/// 各平台数据源（按可靠性排序）：
/// - Android: 原生 `ConnectivityManager`（**首选**；Android 10+ 已禁止应用读
///   `/proc/net/route`，`ip route` 也常被 SELinux 拦）→ `/proc/net/route` → `ip route`
/// - Linux: `ip route show default` → `/proc/net/route`
/// - Windows: `route print -4`（路由表大时可能较慢，给 8 秒）→ PowerShell
///   `Get-NetRoute`（`NextHop`）
/// - macOS: `route -n get default`
///
/// 只做"尽力而为"：拿不到就返回 null，由界面提示手动填写，不要猜
/// （例如按 /24 推 x.x.x.1 在多层路由 / 热点共享下经常是错的）。
Future<String?> getDefaultGateway() async {
  try {
    if (Platform.isAndroid) {
      return await _androidGateway() ??
          _readProcNetRoute() ??
          await _runIpRoute();
    }
    if (Platform.isLinux) {
      return await _runIpRoute() ?? _readProcNetRoute();
    }
    if (Platform.isWindows) {
      // 路由表很大（VPN / Docker / 多网卡）时 route print 会超过 3 秒
      return await _run(
            'route',
            const ['print', '-4'],
            parseWindowsRoutePrint,
            timeout: const Duration(seconds: 8),
          ) ??
          await _run(
            'powershell',
            const [
              '-NoProfile',
              '-NonInteractive',
              '-Command',
              r'(Get-NetRoute -DestinationPrefix 0.0.0.0/0 | Sort-Object RouteMetric | Select-Object -First 1).NextHop',
            ],
            parsePlainIPv4,
            timeout: const Duration(seconds: 10),
          );
    }
    if (Platform.isMacOS) {
      return await _run(
        'route',
        const ['-n', 'get', 'default'],
        parseMacOSRouteGetDefault,
      );
    }
  } catch (_) {}
  return null;
}

/// Android 原生通道：ConnectivityManager 当前网络的默认路由网关
Future<String?> _androidGateway() async {
  try {
    final gateway =
        await _networkChannel.invokeMethod<String>('getDefaultGateway');
    if (gateway != null && _isIPv4(gateway)) return gateway;
  } catch (_) {}
  return null;
}

Future<String?> _runIpRoute() =>
    _run('ip', const ['route', 'show', 'default'], parseIpRouteDefault);

Future<String?> _run(
  String executable,
  List<String> arguments,
  String? Function(String output) parse, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  try {
    final result =
        await Process.run(executable, arguments).timeout(timeout);
    if (result.exitCode != 0) return null;
    return parse(result.stdout.toString());
  } catch (_) {
    return null;
  }
}

String? _readProcNetRoute() {
  try {
    final file = File('/proc/net/route');
    if (!file.existsSync()) return null;
    return parseProcNetRoute(file.readAsStringSync());
  } catch (_) {
    return null;
  }
}

bool _isIPv4(String value) {
  final parts = value.split('.');
  if (parts.length != 4) return false;
  for (final part in parts) {
    final number = int.tryParse(part);
    if (number == null || number < 0 || number > 255) return false;
  }
  return true;
}

/// 解析 `/proc/net/route`：Destination 为 00000000 的那行就是默认路由，
/// Gateway 是**小端**十六进制（0101A8C0 -> 192.168.1.1）。
String? parseProcNetRoute(String output) {
  for (final line in output.split('\n')) {
    final fields = line.trim().split(RegExp(r'\s+'));
    if (fields.length < 3) continue;
    if (!RegExp(r'^[0-9A-Fa-f]{8}$').hasMatch(fields[1])) continue;
    if (fields[1] != '00000000') continue;

    final gateway = int.tryParse(fields[2], radix: 16);
    if (gateway == null || gateway == 0) continue;

    final ip = '${gateway & 0xFF}.'
        '${(gateway >> 8) & 0xFF}.'
        '${(gateway >> 16) & 0xFF}.'
        '${(gateway >> 24) & 0xFF}';
    if (_isIPv4(ip)) return ip;
  }
  return null;
}

/// 解析 `ip route show default`：`default via 192.168.1.1 dev wlan0 ...`
String? parseIpRouteDefault(String output) {
  final match = RegExp(r'default\s+via\s+(\d{1,3}(?:\.\d{1,3}){3})')
      .firstMatch(output);
  final gateway = match?.group(1);
  return gateway != null && _isIPv4(gateway) ? gateway : null;
}

/// 解析 `route print -4`：只认前两列都是 0.0.0.0 的 IPv4 行，
/// `On-link` / `在链路上` 这类非 IP 网关会被过滤掉。
String? parseWindowsRoutePrint(String output) {
  for (final line in output.split('\n')) {
    final fields = line.trim().split(RegExp(r'\s+'));
    if (fields.length < 3) continue;
    if (fields[0] != '0.0.0.0' || fields[1] != '0.0.0.0') continue;
    if (_isIPv4(fields[2])) return fields[2];
  }
  return null;
}

/// 解析 PowerShell `Get-NetRoute` 的 `NextHop` 输出（通常只有一行 IP）。
String? parsePlainIPv4(String output) {
  final match = RegExp(r'\b(\d{1,3}(?:\.\d{1,3}){3})\b').firstMatch(output);
  final gateway = match?.group(1);
  return gateway != null && _isIPv4(gateway) ? gateway : null;
}

/// 解析 `route -n get default`：`gateway: 192.168.1.1`
String? parseMacOSRouteGetDefault(String output) {
  final match =
      RegExp(r'gateway:\s*(\d{1,3}(?:\.\d{1,3}){3})').firstMatch(output);
  final gateway = match?.group(1);
  return gateway != null && _isIPv4(gateway) ? gateway : null;
}
