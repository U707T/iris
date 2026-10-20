import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/hooks/ui/use_full_screen.dart';
import 'package:iris/hooks/ui/use_orientation.dart';
import 'package:iris/hooks/ui/use_remember_window.dart';
import 'package:iris/hooks/ui/use_resize_window.dart';
import 'package:iris/hooks/ui/use_shuffle_on_launch.dart';
import 'package:iris/pages/player/player_view.dart';

class Home extends HookWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext context) {
    useFullScreen();
    useOrientation();
    useResizeWindow();
    useRememberWindow();
    // 随机播放开着的话, 每次启动换一份新的随机顺序
    useShuffleOnLaunch();

    return Scaffold(
      backgroundColor: Colors.black,
      body: const PlayerView(),
    );
  }
}
