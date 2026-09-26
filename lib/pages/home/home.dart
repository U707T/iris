import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/hooks/ui/use_full_screen.dart';
import 'package:iris/hooks/ui/use_orientation.dart';
import 'package:iris/hooks/ui/use_remember_window.dart';
import 'package:iris/hooks/ui/use_resize_window.dart';
import 'package:iris/pages/player/player_view.dart';
import 'package:iris/store/use_app_store.dart';

class Home extends HookWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext context) {
    useFullScreen();
    useOrientation();
    useResizeWindow();
    useRememberWindow();

    final playerBackend =
        useAppStore().select(context, (state) => state.playerBackend);

    return Scaffold(
      backgroundColor: Colors.black,
      body: PlayerView(playerBackend: playerBackend),
    );
  }
}
