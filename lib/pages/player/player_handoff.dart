import 'package:iris/models/player.dart';
import 'package:iris/pages/player/short_video/short_video_pool.dart';
import 'package:iris/utils/logger.dart';

/// 模式切换时的播放器交接 (防"两路声音")。
///
/// 普通模式与短视频模式使用**不同的播放器实例** (宿主切换), 而 media_kit 的
/// [Player.dispose] 是异步的: 内部要先等播放器初始化 / 视频输出就绪 / 释放锁,
/// 若旧播放器还没销毁完, 新播放器已经出声, 就会同时听到两路声音 —— 操作过快
/// (例如刚点开视频就切进短视频模式、快速进出模式) 时尤其明显。
///
/// 这里记录当前宿主正在使用的播放器, 切换模式前先显式暂停它, 让声音立刻停掉;
/// 销毁照旧异步进行, 只是不再有机会出声。
///
/// 说明: 只有 Media Kit 的两个宿主会注册 (普通播放器 / 短视频预载池), 它们会在
/// 模式切换时被替换; FVP 后端两种模式共用同一个播放器, 不注册也不需要交接。
MediaPlayer? _active;

/// 当前宿主注册的播放器 (未注册时为 null)
MediaPlayer? get activeHandoffPlayer => _active;

/// 宿主挂载 / 重建时注册自己使用的播放器
void registerActivePlayer(MediaPlayer player) {
  _active = player;
}

/// 宿主卸载时注销 (仅在仍指向自己时清除, 避免覆盖新宿主的注册)
void unregisterActivePlayer(MediaPlayer player) {
  if (identical(_active, player)) {
    _active = null;
  }
}

/// 切换模式前调用: 立即让当前宿主的播放器静音。
///
/// 短视频池需要暂停全部槽位 (避免个别槽位还在播放); 普通播放器暂停即可,
/// 它的进度保存与销毁由宿主卸载时的清理逻辑负责。
Future<void> silenceActivePlayer() async {
  final player = _active;
  if (player == null) return;
  try {
    if (player is ShortVideoMediaKitPlayer) {
      player.pool.silence();
    } else {
      await player.pause();
    }
  } catch (e) {
    logger('Silence active player error: $e');
  }
}
