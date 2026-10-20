import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flutter/foundation.dart';
import 'package:iris/models/storages/storage.dart';

part 'file.freezed.dart';
part 'file.g.dart';

enum ContentType {
  video,
  audio,
  image,
  other,
}

enum FileOptions {
  addToPlayQueue,
  remove,
  openInFolder,
}

@freezed
abstract class FileItem with _$FileItem {
  const FileItem._();
  const factory FileItem({
    @Default('') String storageId,
    @Default(StorageType.none) StorageType storageType,
    required String name,
    required String uri,
    @Default([]) List<String> path,
    @Default(false) bool isDir,
    @Default(0) int size,
    DateTime? lastModified,
    @Default(ContentType.video) ContentType type,
  }) = _FileItem;

  factory FileItem.fromJson(Map<String, dynamic> json) =>
      _$FileItemFromJson(json);

  String getID() => '$storageId:$uri';
}

@freezed
abstract class PlayQueueItem with _$PlayQueueItem {
  const factory PlayQueueItem({
    required FileItem file,
    required int index,
  }) = _PlayQueueItem;

  factory PlayQueueItem.fromJson(Map<String, dynamic> json) =>
      _$PlayQueueItemFromJson(json);
}
