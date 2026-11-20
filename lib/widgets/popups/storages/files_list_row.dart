import 'package:material_ui/material_ui.dart';
import 'package:iris/models/file.dart';
import 'package:iris/store/use_history_store.dart';
import 'package:iris/utils/file_size_convert.dart';
import 'package:iris/utils/format_date_time.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/playback_progress.dart';
import 'package:iris/widgets/media_row.dart';

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

    final meta = [
      if (file.size != 0) '${fileSizeConvert(file.size)} MB',
      if (file.lastModified != null) formatShortDateTime(file.lastModified!),
    ].join(' · ');

    return MediaRow(
      icon: () {
        if (file.isDir == true && file.name.isNotEmpty) {
          return Icons.folder_rounded;
        }
        return switch (file.type) {
          ContentType.video => Icons.movie_rounded,
          ContentType.audio => Icons.audiotrack_rounded,
          ContentType.image => Icons.image_rounded,
          ContentType.other => Icons.file_copy_rounded,
        };
      }(),
      title: file.name,
      meta: meta.isEmpty ? null : meta,
      progress: playbackProgressLabel(useHistoryStore().findById(file.getID())),
      menu: isPlayable
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
