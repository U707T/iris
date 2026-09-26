import 'package:material_ui/material_ui.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:iris/utils/platform.dart';
import 'package:window_manager/window_manager.dart';

class DragArea extends StatelessWidget {
  const DragArea({
    super.key,
    required this.child,
  });

  final Widget child;
  @override
  Widget build(BuildContext context) {
    final isFullScreen =
        usePlayerUiStore().select(context, (state) => state.isFullScreen);

    return GestureDetector(
      onDoubleTap: () async {
        if (!isDesktop) return;
        if (isFullScreen) {
          await usePlayerUiStore().updateFullScreen(false);
        } else {
          if (await windowManager.isMaximized()) {
            await windowManager.unmaximize();
          } else {
            await windowManager.maximize();
          }
        }
      },
      onPanStart: (details) async {
        if (isDesktop) {
          windowManager.startDragging();
        }
      },
      child: child,
    );
  }
}
