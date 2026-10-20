import 'package:flutter/foundation.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:material_ui/material_ui.dart';

/// 依赖与许可。
///
/// 数据来自 Flutter 构建时生成的 NOTICES (即 `LicenseRegistry`), 不再在
/// Dart 代码里内嵌一份几百 KB 的许可文本 (旧实现: `lib/oss_licenses.dart`,
/// 619KB 源码 / 300KB 字符串, 与 NOTICES 内容重复)。
class Dependencies extends HookWidget {
  const Dependencies({super.key});

  static const title = 'Libraries';

  @override
  Widget build(BuildContext context) {
    final entriesFuture =
        useMemoized(() => LicenseRegistry.licenses.toList(), const []);
    final snapshot = useFuture(entriesFuture);

    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }

    // 按包名归并 (一个包可能有多段许可文本)
    final Map<String, List<String>> grouped = {};
    for (final entry in snapshot.data ?? const <LicenseEntry>[]) {
      final name =
          entry.packages.isEmpty ? 'unknown' : entry.packages.join(', ');
      grouped
          .putIfAbsent(name, () => [])
          .addAll(entry.paragraphs.map((p) => p.text));
    }
    final names = grouped.keys.toList()..sort();

    if (names.isEmpty) {
      return const Center(child: Text('No licenses'));
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: names.length,
      itemBuilder: (context, index) {
        final name = names[index];
        return ListTile(
          leading: const Icon(Icons.code_rounded),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
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
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
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
}
