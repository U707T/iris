import 'package:material_ui/material_ui.dart';
import 'package:iris/widgets/popups/track/audio_track_list.dart';
import 'package:iris/utils/get_localizations.dart';

/// 音轨面板 (字幕功能已移除, 只保留音轨切换)。
class TrackPanel extends StatelessWidget {
  const TrackPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: Card(
            color: Colors.transparent,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: const AudioTrackList(),
          ),
        ),
        Divider(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
          height: 0,
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
          child: Row(
            children: [
              Text(
                t.audio_track,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              IconButton(
                tooltip: '${t.close} ( Escape )',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
