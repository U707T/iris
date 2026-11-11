import 'package:flutter_test/flutter_test.dart';
import 'package:iris/globals.dart'
    show maxZoom, minZoom, zoomSnapThreshold, zoomStep;
import 'package:iris/store/use_player_ui_store.dart';

/// 画面缩放的「手感」: 100% 附近一个窄死区, 手动缩放落进来就贴回原始大小。
///
/// 断言的是 [resolveZoom] 的落点, 不是某个按钮 —— 双指捏合、`Ctrl + 滚轮`、
/// 缩放面板走的是同一个入口, 这里守住的就是三者共用的规则。
void main() {
  test('死区内吸附回精确的 1.0', () {
    for (final double zoom in <double>[
      1.0,
      1.02,
      0.98,
      1.0 + zoomSnapThreshold / 2,
      1.0 - zoomSnapThreshold / 2,
    ]) {
      expect(resolveZoom(zoom), 1.0, reason: '$zoom 应吸附回 100%');
    }
  });

  test('死区外原样保留', () {
    for (final double zoom in <double>[0.5, 0.9, 1.04, 1.2, 2.0, 4.99]) {
      expect(resolveZoom(zoom), zoom);
    }
  });

  test('夹取还在: 越界值收到 min / max', () {
    expect(resolveZoom(0.01), minZoom);
    expect(resolveZoom(9.0), maxZoom);
  });

  test('缩放面板的 + / - 一步就能走出死区', () {
    // 死区必须窄于 zoomStep, 否则「+」从 100% 出发会被吸回来, 按钮像坏了
    expect(resolveZoom(1.0 + zoomStep), greaterThan(1.0 + zoomSnapThreshold));
    expect(resolveZoom(1.0 - zoomStep), lessThan(1.0 - zoomSnapThreshold));
  });

  test('store 里存的是吸附后的值', () {
    final store = usePlayerUiStore();

    store.updateZoom(1.02);
    expect(store.state.zoom, 1.0);

    store.updateZoom(1.5);
    expect(store.state.zoom, 1.5);

    store.updateZoom(0.99);
    expect(store.state.zoom, 1.0);

    store.updateZoom(3.0);
    store.resetZoom();
    expect(store.state.zoom, 1.0);
  });
}
