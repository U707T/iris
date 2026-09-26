import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:material_ui/material_ui.dart';

/// material_ui 版 TabController。
///
/// flutter_hooks 的 `useTabController` 返回的仍是 SDK 旧版 Material 的
/// TabController, 与 material_ui 的 TabBar / TabBarView 不兼容,
/// 这里手动创建 material_ui 的 TabController 并处理释放。
TabController useMaterialTabController({required int initialLength}) {
  final vsync = useSingleTickerProvider();
  final controller = useMemoized(
    () => TabController(length: initialLength, vsync: vsync),
    [vsync, initialLength],
  );
  useEffect(() => () => controller.dispose(), [controller]);
  return controller;
}
