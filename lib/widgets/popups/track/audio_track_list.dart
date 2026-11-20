import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/models/player.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/widgets/media_row.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

class AudioTrackList extends HookWidget {
  const AudioTrackList({super.key});

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);

    final player = context.read<MediaPlayer>();

    final focusNode = useFocusNode();

    useEffect(() {
      focusNode.requestFocus();
      return () => focusNode.unfocus();
    }, []);

    if (player is MediaKitPlayer) {
      return ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          ...player.audios.map(
            (audio) => MediaRow(
              icon: Icons.graphic_eq_rounded,
              title: audio == AudioTrack.auto()
                  ? t.auto
                  : audio == AudioTrack.no()
                  ? t.off
                  : audio.title ?? audio.language ?? audio.id,
              selected: player.audio == audio,
              focusNode: player.audio == audio ? focusNode : null,
              onTap: () {
                logger(
                  'Set audio track: ${audio.title ?? audio.language ?? audio.id}',
                );
                player.player.setAudioTrack(audio);
                Navigator.of(context).pop();
              },
            ),
          ),
        ],
      );
    }

    return Container();
  }
}
