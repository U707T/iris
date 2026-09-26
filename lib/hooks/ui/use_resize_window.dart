import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/file.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/utils/platform.dart';
import 'package:window_manager/window_manager.dart';
import 'package:window_size/window_size.dart';

Future<void> _applyResize(Rect newBounds) async {
  if (await windowManager.isFullScreen() || await windowManager.isMaximized()) {
    return;
  }
  await windowManager.setBounds(newBounds, animate: true);
}

void useResizeWindow() {
  final context = useContext();

  final autoResize = useAppStore().select(context, (state) => state.autoResize);
  final isFullScreen =
      usePlayerUiStore().select(context, (state) => state.isFullScreen);
  final aspectRatio =
      usePlayerUiStore().select(context, (state) => state.aspectRatio);

  final currentPlay = usePlayQueueStore().select(context, (state) {
    final index =
        state.playQueue.indexWhere((e) => e.index == state.currentIndex);
    return index != -1 ? state.playQueue[index] : null;
  });
  final contentType = currentPlay?.file.type ?? ContentType.other;

  final prevIsFullScreen = usePrevious(isFullScreen);
  final prevAspectRatio = usePrevious(aspectRatio);

  useEffect(() {
    if (!isDesktop) return;

    Future<void> performResize() async {
      if (isFullScreen) return;

      if (!autoResize) {
        await windowManager.setAspectRatio(0);
        return;
      }

      if (contentType == ContentType.audio) {
        await windowManager.setAspectRatio(0);
        return;
      }

      if (contentType == ContentType.video) {
        if (aspectRatio <= 0) {
          await windowManager.setAspectRatio(0);
          return;
        }

        await windowManager.setAspectRatio(aspectRatio);
        final oldBounds = await windowManager.getBounds();
        final screen = await getCurrentScreen();
        if (screen == null) return;

        if (oldBounds.size.aspectRatio.toStringAsFixed(2) ==
            aspectRatio.toStringAsFixed(2)) {
          return;
        }

        Size newSize;
        final bool isPreviousPortrait = (prevAspectRatio ?? 1.0) < 1.0;
        final bool isCurrentLandscape = aspectRatio >= 1.0;

        if (isPreviousPortrait && isCurrentLandscape) {
          logger('Resize rule: Portrait to Landscape (Height-based)');
          double newHeight = oldBounds.height;
          double newWidth = newHeight * aspectRatio;
          newSize = Size(newWidth, newHeight);
        } else {
          logger('Resize rule: Standard (Normalized Area-based)');
          double currentArea = oldBounds.width * oldBounds.height;
          const double standardAspectRatio = 16.0 / 9.0;
          double normalizedHeight =
              math.sqrt(currentArea / standardAspectRatio);

          double newHeight = normalizedHeight;
          double newWidth = newHeight * aspectRatio;
          newSize = Size(newWidth, newHeight);
        }

        double maxWidth = screen.frame.width / screen.scaleFactor * 0.95;
        double maxHeight = screen.frame.height / screen.scaleFactor * 0.95;

        if (newSize.width > maxWidth) {
          newSize = Size(maxWidth, maxWidth / aspectRatio);
        }
        if (newSize.height > maxHeight) {
          newSize = Size(maxHeight * aspectRatio, maxHeight);
        }

        final newPosition = Offset(
          oldBounds.left + (oldBounds.width - newSize.width) / 2,
          oldBounds.top + (oldBounds.height - newSize.height) / 2,
        );

        await _applyResize(Rect.fromLTWH(
            newPosition.dx, newPosition.dy, newSize.width, newSize.height));
      }
    }

    final wasFullScreen = prevIsFullScreen == true;
    if (wasFullScreen && !isFullScreen) {
      Future.delayed(const Duration(milliseconds: 50), performResize);
    } else {
      performResize();
    }

    return null;
  }, [
    autoResize,
    isFullScreen,
    aspectRatio,
    contentType,
  ]);
}
