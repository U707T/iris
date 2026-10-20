import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:media_kit/media_kit.dart';

/// media_kit 流的一次性快照（供 UI 组装 [MediaPlayer] 使用）。
///
/// 所有 `player.stream.*` 的订阅都集中在这里，主 hook 只读字段，
/// 不再散落 8 个 useStream。
class PlayerStreams {
  PlayerStreams({
    required this.playing,
    required this.videoParams,
    required this.position,
    required this.duration,
    required this.buffer,
    required this.completed,
    required this.audio,
    required this.audios,
  });

  final bool playing;
  final VideoParams? videoParams;
  final Duration position;
  final Duration duration;
  final Duration buffer;
  final bool completed;
  final AudioTrack audio;
  final List<AudioTrack> audios;
}

PlayerStreams usePlayerStreams(Player player) {
  final playingStream = useMemoized(() => player.stream.playing, const []);
  final playing = useStream(playingStream).data ?? false;

  final videoParamsStream =
      useMemoized(() => player.stream.videoParams, const []);
  final videoParams = useStream(videoParamsStream).data;

  final positionStream = useMemoized(() => player.stream.position, const []);
  final position = useStream(positionStream).data ?? Duration.zero;

  final durationStream = useMemoized(() => player.stream.duration, const []);
  final duration = useStream(durationStream).data ?? Duration.zero;

  final bufferStream = useMemoized(() => player.stream.buffer, const []);
  final buffer = useStream(bufferStream).data ?? Duration.zero;

  final completedStream = useMemoized(() => player.stream.completed, const []);
  final completed = useStream(completedStream).data ?? false;

  final trackStream = useMemoized(() => player.stream.track, const []);
  final track = useStream(trackStream).data;
  final audio = useMemoized(
    () => track?.audio ?? AudioTrack.no(),
    [track?.audio],
  );

  final tracksStream = useMemoized(() => player.stream.tracks, const []);
  final tracks = useStream(tracksStream).data;
  final audios = useMemoized(
    () => tracks?.audio ?? const <AudioTrack>[],
    [tracks?.audio],
  );

  return PlayerStreams(
    playing: playing,
    videoParams: videoParams,
    position: position,
    duration: duration,
    buffer: buffer,
    completed: completed,
    audio: audio,
    audios: audios,
  );
}
