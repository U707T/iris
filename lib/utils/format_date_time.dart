/// `2026-11-12 18:06`，本地时间，精确到分钟。
///
/// 列表里的日期是次要信息：秒和时区都不该占位置。
String formatShortDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
