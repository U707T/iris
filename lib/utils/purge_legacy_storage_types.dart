/// 已从产品中移除的存储类型。
///
/// 旧版本可能把它们写进了状态 (播放队列 / 历史): 这些枚举值现在已经不存在,
/// `fromJson` 会直接抛异常, 导致**整份**状态被丢弃。所以在反序列化前先把这些
/// 条目剔掉 —— 只丢它们, 其余队列 / 历史照常恢复。
const Set<String> kRemovedStorageTypes = {'ftp'};

bool _usesRemovedStorageType(dynamic entry) {
  if (entry is! Map) return false;
  final file = entry['file'];
  if (file is! Map) return false;
  return kRemovedStorageTypes.contains('${file['storageType']}');
}

/// 清洗播放队列 JSON。返回清洗后的数据; 队列被清空时返回 null (视为无状态)。
Map<String, dynamic>? sanitizePlayQueueJson(dynamic data) {
  if (data is! Map<String, dynamic>) return null;
  final queue = data['playQueue'];
  if (queue is! List) return data;

  final removed = queue.any(_usesRemovedStorageType);
  if (!removed) return data;

  final kept = queue.where((e) => !_usesRemovedStorageType(e)).toList();
  if (kept.isEmpty) return null;

  final int currentIndex = data['currentIndex'] is int
      ? data['currentIndex'] as int
      : 0;
  final bool currentKept = kept.any((e) => e is Map && e['index'] == currentIndex);

  return {
    ...data,
    'playQueue': kept,
    if (!currentKept) 'currentIndex': (kept.first as Map)['index'] ?? 0,
  };
}

/// 清洗播放历史 JSON, 去掉指向已移除存储类型的条目。
Map<String, dynamic>? sanitizeHistoryJson(dynamic data) {
  if (data is! Map<String, dynamic>) return null;
  final history = data['history'];
  if (history is! Map) return data;

  if (!history.values.any(_usesRemovedStorageType)) return data;

  final cleaned = <String, dynamic>{};
  history.forEach((key, value) {
    if (!_usesRemovedStorageType(value)) cleaned['$key'] = value;
  });
  return {...data, 'history': cleaned};
}
