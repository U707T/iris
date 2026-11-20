import 'package:flutter/foundation.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:material_ui/material_ui.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/panel.dart';

/// 依赖与许可。
///
/// 数据来自 Flutter 构建时生成的 NOTICES (即 `LicenseRegistry`), 不再在
/// Dart 代码里内嵌一份几百 KB 的许可文本 (旧实现: `lib/oss_licenses.dart`,
/// 619KB 源码 / 300KB 字符串, 与 NOTICES 内容重复)。
///
/// 它不再占一个设置页签: 一份按包名排序的许可清单与「语言 / 主题」不是
/// 同一个层级, 从关于页的一行进去就够了。
Future<void> showDependenciesDialog(BuildContext context) async =>
    await showDialog<void>(
      context: context,
      builder: (context) => const DependenciesDialog(),
    );

class DependenciesDialog extends HookWidget {
  const DependenciesDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);

    final entriesFuture = useMemoized(
      () => LicenseRegistry.licenses.toList(),
      const [],
    );
    final snapshot = useFuture(entriesFuture);

    Widget content;
    if (snapshot.connectionState == ConnectionState.waiting) {
      content = const Center(child: CircularProgressIndicator());
    } else {
      // 按包名归并 (一个包可能有多段许可文本)
      final Map<String, List<String>> grouped = {};
      for (final entry in snapshot.data ?? const <LicenseEntry>[]) {
        final name = entry.packages.isEmpty
            ? 'unknown'
            : entry.packages.join(', ');
        grouped
            .putIfAbsent(name, () => [])
            .addAll(entry.paragraphs.map((p) => p.text));
      }
      final names = grouped.keys.toList()..sort();

      content = names.isEmpty
          ? PanelEmpty(label: t.no_licenses)
          : ListView.builder(
              itemCount: names.length,
              itemBuilder: (context, index) {
                final name = names[index];
                return ListTile(
                  leading: const Icon(Icons.code_rounded, size: 20),
                  title: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => showModalBottomSheet(
                    context: context,
                    enableDrag: true,
                    builder: (context) => SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 16),
                          SelectableText(grouped[name]!.join('\n\n')),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
    }

    return AlertDialog(
      title: Text(t.dependencies),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: SizedBox(width: 420, height: 480, child: content),
    );
  }
}
