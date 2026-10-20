import 'package:flutter_test/flutter_test.dart';
import 'package:iris/utils/default_gateway.dart';

/// 默认网关解析（WebDAV 对话框"读取默认网关"按钮的数据源）。
/// 只测纯解析：不同系统的真实输出格式。
void main() {
  test('/proc/net/route: 默认路由的 Gateway 是小端十六进制', () {
    const output = 'Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric'
        '\tMask\t\tMTU\tWindow\tIRTT\n'
        'wlan0\t00000000\t0101A8C0\t0003\t0\t0\t0\t00000000\t0\t0\t0\n'
        'wlan0\t0001A8C0\t00000000\t0001\t0\t0\t0\t00FFFFFF\t0\t0\t0\n';

    expect(parseProcNetRoute(output), '192.168.1.1');
  });

  test('/proc/net/route: 没有默认路由时返回 null', () {
    const output = 'Iface\tDestination\tGateway\n'
        'wlan0\t0001A8C0\t00000000\t0001\n';

    expect(parseProcNetRoute(output), isNull);
  });

  test('ip route: default via 取第一段 IPv4', () {
    expect(
      parseIpRouteDefault('default via 10.0.0.1 dev wlan0 proto dhcp metric 600'),
      '10.0.0.1',
    );
    expect(parseIpRouteDefault('192.168.1.0/24 dev wlan0'), isNull);
  });

  test('Windows route print: 跳过 On-link / 在链路上', () {
    const output = '''
===========================================================================
IPv4 Route Table
===========================================================================
          0.0.0.0          0.0.0.0      192.168.1.1    192.168.1.100     25
        127.0.0.0        255.0.0.0         On-link         127.0.0.1    331
''';

    expect(parseWindowsRoutePrint(output), '192.168.1.1');
  });

  test('Windows route print: 只有 On-link 时返回 null', () {
    const output = '          0.0.0.0          0.0.0.0         On-link         10.0.0.2    331\n';
    expect(parseWindowsRoutePrint(output), isNull);
  });

  test('macOS route -n get default: gateway 行', () {
    const output = '''   route to: default
destination: default
       mask: default
    gateway: 192.168.31.1
  interface: en0
''';

    expect(parseMacOSRouteGetDefault(output), '192.168.31.1');
  });

  test('macOS: 没有 gateway 行时返回 null', () {
    expect(parseMacOSRouteGetDefault('route: bad address: default'), isNull);
  });

  test('非法 IPv4 不会被当成网关', () {
    expect(
      parseWindowsRoutePrint('0.0.0.0 0.0.0.0 999.1.1.1 10.0.0.2 25'),
      isNull,
    );
  });
}
