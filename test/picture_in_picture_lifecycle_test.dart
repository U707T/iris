import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/hooks/player/use_picture_in_picture.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/persistence/json_persistence.dart';
import 'package:iris/store/persistence/key_value_store.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:iris/utils/picture_in_picture.dart';
import 'package:provider/provider.dart';
// ignore: depend_on_referenced_packages
import 'package:zustand/zustand.dart';

class _MemoryStore implements KeyValueStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
  @override
  Future<void> delete(String key) async {}
}

MediaPlayer _player() => MediaPlayer(
  isInitializing: false,
  isPlaying: false,
  position: Duration.zero,
  duration: const Duration(minutes: 1),
  buffer: Duration.zero,
  width: 1920,
  height: 1080,
  saveProgress: () async {},
  play: () async {},
  pause: () async {},
  backward: (_) async {},
  forward: (_) async {},
  stepBackward: () async {},
  stepForward: () async {},
  seek: (_) async {},
);

void main() {
  testWidgets(
    'replacement host retains its PiP callback after old host unmount',
    (tester) async {
      final appStore = AppStore(
        persistence: JsonPersistence<AppState>(
          store: _MemoryStore(),
          key: 'app',
          fromJson: AppState.fromJson,
          toJson: (state) => state.toJson(),
        ),
      );
      final uiStore = PlayerUiStore();
      StoreLocator().put(AppStore, appStore);
      StoreLocator().put(PlayerUiStore, uiStore);
      await tester.pump();
      await appStore.ready;
      final host = ValueNotifier(0);
      PictureInPicture.onModeChanged = null;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.idle();
        final cleanup = () async {
          PictureInPicture.onModeChanged = null;
          host.dispose();
          final locator = StoreLocator();
          await locator.delete(AppStore);
          await locator.delete(PlayerUiStore);
          await locator.dispose();
        }();
        await tester.pump();
        await tester.idle();
        await cleanup;
      });

      await tester.pumpWidget(
        Provider<StoreLocator>.value(
          value: StoreLocator(),
          child: Provider<MediaPlayer>.value(
            value: _player(),
            child: ValueListenableBuilder<int>(
              valueListenable: host,
              builder: (_, mode, _) => HookBuilder(
                key: ValueKey(mode),
                builder: (_) {
                  usePictureInPicture(
                    file: const FileItem(name: 'a', uri: '/a.mp4'),
                    hasOverlay: false,
                  );
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
      final initialHandler = PictureInPicture.onModeChanged;
      expect(initialHandler, isNotNull);
      initialHandler!(true);
      expect(uiStore.state.isPictureInPicture, isTrue);

      // Different keys replace the hook host, matching normal/short-video hosts:
      // the replacement mounts during build and the old host unmounts afterward.
      host.value = 1;
      await tester.pump();
      final shortHandler = PictureInPicture.onModeChanged;
      expect(shortHandler, isNotNull);
      expect(identical(shortHandler, initialHandler), isFalse);
      uiStore.updateIsShowControl(false);
      shortHandler!(false);
      expect(uiStore.state.isPictureInPicture, isFalse);
      expect(uiStore.state.isShowControl, isTrue);

      host.value = 2;
      await tester.pump();
      final normalHandler = PictureInPicture.onModeChanged;
      expect(normalHandler, isNotNull);
      expect(identical(normalHandler, shortHandler), isFalse);
      normalHandler!(true);
      expect(uiStore.state.isPictureInPicture, isTrue);
      normalHandler(false);
      expect(uiStore.state.isPictureInPicture, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(
        PictureInPicture.onModeChanged,
        isNull,
        reason: 'the final owner still unregisters itself on unmount',
      );
    },
  );
}
