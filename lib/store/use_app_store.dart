import 'package:material_ui/material_ui.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/globals.dart' as globals;
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/persistence/json_persistence.dart';
import 'package:iris/store/persistence/key_value_store.dart';
import 'package:iris/store/persistent_store.dart';
import 'package:iris/utils/logger.dart';

class AppStore extends PersistentStore<AppState> {
  AppStore({JsonPersistence<AppState>? persistence})
    : super(
        AppState(),
        persistence ??
            JsonPersistence<AppState>(
              // 设置体积会随版本增长, 放应用私有文件; 加密存储只留给凭据。
              store: FileKeyValueStore(),
              // 旧版本把设置写在 secure storage 里: 首次读取自动迁移。
              legacyStore: SecureKeyValueStore.instance,
              legacyKey: 'app_state',
              key: 'app_state',
              fromJson: (json) =>
                  AppState.fromJson(json)
                      .copyWith(autoPlay: globals.autoPlayOnLaunch),
              toJson: (state) => state.toJson(),
            ),
      );

  Future<void> updateAutoPlay(bool autoPlay) async {
    if (!isLoaded) await ready;
    set(state.copyWith(autoPlay: autoPlay));
  }

  Future<void> updateShuffle(bool shuffle) async {
    if (!isLoaded) await ready;
    set(state.copyWith(shuffle: shuffle));
    await save(state);
  }

  Future<void> updateRepeat(Repeat repeat) async {
    if (!isLoaded) await ready;
    set(state.copyWith(repeat: repeat));
    await save(state);
  }

  Future<void> toggleRepeat() async {
    if (!isLoaded) await ready;
    switch (state.repeat) {
      case Repeat.none:
        set(state.copyWith(repeat: Repeat.one));
        break;
      case Repeat.one:
        set(state.copyWith(repeat: Repeat.all));
        break;
      case Repeat.all:
        set(state.copyWith(repeat: Repeat.none));
        break;
    }
    await save(state);
  }

  Future<void> updateFit(BoxFit fit) async {
    if (!isLoaded) await ready;
    set(state.copyWith(fit: fit));
    await save(state);
  }

  Future<void> toggleFit() async {
    if (!isLoaded) await ready;
    switch (state.fit) {
      case BoxFit.contain:
        set(state.copyWith(fit: BoxFit.fill));
        break;
      case BoxFit.fill:
        set(state.copyWith(fit: BoxFit.cover));
        break;
      case BoxFit.cover:
        set(state.copyWith(fit: BoxFit.none));
        break;
      case BoxFit.none:
        set(state.copyWith(fit: BoxFit.contain));
        break;
      default:
        break;
    }
    await save(state);
  }

  Future<void> updateRate(double value, {bool persist = true}) async {
    if (!isLoaded) await ready;
    logger('updateRate: $value');
    set(state.copyWith(rate: value));
    if (persist) await save(state);
  }

  Future<void> updateLongPressSpeed(double value) async {
    if (!isLoaded) await ready;
    set(state.copyWith(longPressSpeed: value));
    await save(state);
  }

  Future<void> updateVolume(int volume, {bool persist = true}) async {
    if (!isLoaded) await ready;
    set(
      state.copyWith(
        volume: volume < 0
            ? 0
            : volume > 100
            ? 100
            : volume,
      ),
    );
    if (persist) await save(state);
  }

  Future<void> updateMute(bool isMuted, {bool persist = true}) async {
    if (!isLoaded) await ready;
    set(state.copyWith(isMuted: isMuted));
    if (persist) await save(state);
  }

  Future<void> toggleMute() async {
    if (!isLoaded) await ready;
    set(state.copyWith(isMuted: !state.isMuted));
    await save(state);
  }

  Future<void> updateThemeMode(ThemeMode themeMode) async {
    if (!isLoaded) await ready;
    set(state.copyWith(themeMode: themeMode));
    await save(state);
  }

  Future<void> updateLanguage(String language) async {
    if (!isLoaded) await ready;
    set(state.copyWith(language: language));
    await save(state);
  }

  Future<void> toggleAutoResize() async {
    if (!isLoaded) await ready;
    set(state.copyWith(autoResize: !state.autoResize));
    await save(state);
  }

  Future<void> toggleAlwaysPlayFromBeginning() async {
    if (!isLoaded) await ready;
    set(
      state.copyWith(alwaysPlayFromBeginning: !state.alwaysPlayFromBeginning),
    );
    await save(state);
  }

  Future<void> toggleAutoHideControls() async {
    if (!isLoaded) await ready;
    set(state.copyWith(autoHideControls: !state.autoHideControls));
    await save(state);
  }

  Future<void> updateControlHideDelay(int seconds) async {
    if (!isLoaded) await ready;
    set(state.copyWith(controlHideDelaySeconds: seconds));
    await save(state);
  }

  Future<void> updateSortBy(SortBy sortBy) async {
    if (!isLoaded) await ready;
    set(state.copyWith(sortBy: sortBy));
    await save(state);
  }

  Future<void> updateSortOrder(SortOrder sortOrder) async {
    if (!isLoaded) await ready;
    set(state.copyWith(sortOrder: sortOrder));
    await save(state);
  }

  Future<void> updateFolderFirst(bool folderFirst) async {
    if (!isLoaded) await ready;
    set(state.copyWith(folderFirst: folderFirst));
    await save(state);
  }

  Future<void> updateOrientation(ScreenOrientation orientation) async {
    if (!isLoaded) await ready;
    set(state.copyWith(orientation: orientation));
    await save(state);
  }

  Future<void> updateSeekStep(int seconds) async {
    if (!isLoaded) await ready;
    set(state.copyWith(seekStepSeconds: seconds));
    await save(state);
  }

  Future<void> updateSeekStepLarge(int seconds) async {
    if (!isLoaded) await ready;
    set(state.copyWith(seekStepLargeSeconds: seconds));
    await save(state);
  }

  Future<void> togglePureBlackTheme() async {
    if (!isLoaded) await ready;
    set(state.copyWith(pureBlackTheme: !state.pureBlackTheme));
    await save(state);
  }

  Future<void> toggleRememberWindowSize() async {
    if (!isLoaded) await ready;
    set(state.copyWith(rememberWindowSize: !state.rememberWindowSize));
    await save(state);
  }

  Future<void> togglePictureInPicture() async {
    if (!isLoaded) await ready;
    set(state.copyWith(pictureInPicture: !state.pictureInPicture));
    await save(state);
  }

  Future<void> updateWindowBounds(
    List<double>? bounds, {
    bool? maximized,
  }) async {
    if (!isLoaded) await ready;
    set(
      state.copyWith(
        windowBounds: bounds,
        windowMaximized: maximized ?? state.windowMaximized,
      ),
    );
    await save(state);
  }

  @override
  Future<AppState?> load() => loadPersisted();
}

AppStore useAppStore() => create(() => AppStore());
