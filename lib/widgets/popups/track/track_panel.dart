import 'package:material_ui/material_ui.dart';
import 'package:iris/widgets/panel.dart';
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
        PanelHeader(title: Text(t.audio_track)),
        const PanelDivider(),
        const Flexible(child: AudioTrackList()),
      ],
    );
  }
}
