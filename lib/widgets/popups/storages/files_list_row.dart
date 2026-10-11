import 'package:material_ui/material_ui.dart' hide Chip;
import 'package:iris/models/file.dart';
import 'package:iris/models/progress.dart';
import 'package:iris/store/use_history_store.dart';
import 'package:iris/utils/file_size_convert.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/chip.dart';

/// 文件列表的单个条目:
/// 目录 = 进入; 视频 / 音频 = 播放; 右侧菜单可加入播放队列。
class FilesListRow extends StatelessWidget {
  const FilesListRow({
    super.key,
    required this.file,
    required this.onTap,
    required this.onAddToPlayQueue,
  });

  final FileItem file;
  final void Function() onTap;
  final void Function() onAddToPlayQueue;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final isPlayable =
        file.type == ContentType.video || file.type == ContentType.audio;

    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
      visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
      leading: () {
        if (file.isDir == true && file.name.isNotEmpty) {
          return const Icon(Icons.folder_rounded);
        }
        switch (file.type) {
          case ContentType.video:
            return const Icon(Icons.movie_rounded);
          case ContentType.audio:
            return const Icon(Icons.audiotrack_rounded);
          case ContentType.image:
            return const Icon(Icons.image_rounded);
          case ContentType.other:
            return const Icon(Icons.file_copy_rounded);
        }
      }(),
      title: Text(
        file.name,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        mainAxisSize: MainAxisSize.min,
        textBaseline: TextBaseline.ideographic,
        children: [
          if (file.size != 0)
            Text(
              "${fileSizeConvert(file.size)} MB",
              style: const TextStyle(
                fontSize: 13,
              ),
            ),
          if (file.size != 0) const SizedBox(width: 8),
          if (file.lastModified != null)
            Expanded(
              child: Text(
                file.lastModified.toString().split('.')[0],
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withValues(alpha: 0.8),
                  fontWeight: FontWeight.w400,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          if (file.size != 0) const SizedBox(width: 8),
          () {
            final Progress? progress = useHistoryStore().findById(file.getID());
            if (progress != null && progress.file.type == ContentType.video) {
              if ((progress.duration.inMilliseconds -
                      progress.position.inMilliseconds) <=
                  5000) {
                return Chip(text: '100%');
              }
              final String progressString = (progress.position.inMilliseconds /
                      progress.duration.inMilliseconds *
                      100)
                  .toStringAsFixed(0);
              return Chip(text: '$progressString %');
            } else {
              return const SizedBox();
            }
          }(),
          ...file.subtitles
              .map((subtitle) => subtitle.uri.split('.').last.toUpperCase())
              .toSet()
              .toList()
              .map(
                (subtitleType) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 4),
                    Chip(
                      text: subtitleType,
                      primary: true,
                    ),
                  ],
                ),
              ),
        ],
      ),
      trailing: isPlayable
          ? PopupMenuButton<FileOptions>(
              clipBehavior: Clip.hardEdge,
              constraints: const BoxConstraints(minWidth: 200),
              onSelected: (value) async {
                switch (value) {
                  case FileOptions.addToPlayQueue:
                    onAddToPlayQueue();
                    break;
                  default:
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: FileOptions.addToPlayQueue,
                  child: Text(t.add_to_play_queue),
                ),
              ],
            )
          : null,
      onTap: onTap,
    );
  }
}
