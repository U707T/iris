import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/persistent_store.dart';
import 'package:iris/utils/logger.dart';

class AppStore extends PersistentStore<AppState> {
  AppStore() : super(AppState());

  Future<void> updateAutoPlay(bool autoPlay) async =>
      set(state.copyWith(autoPlay: autoPlay));

  Future<void> updateShuffle(bool shuffle) async {
    set(state.copyWith(shuffle: shuffle));
    await save(state);
  }

  Future<void> updateRepeat(Repeat repeat) async {
    set(state.copyWith(repeat: repeat));
    await save(state);
  }

  Future<void> toggleRepeat() async {
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
    set(state.copyWith(fit: fit));
    await save(state);
  }

  Future<void> toggleFit() async {
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
    logger('updateRate: $value');
    set(state.copyWith(rate: value));
    if (persist) await save(state);
  }

  Future<void> updateLongPressSpeed(double value) async {
    set(state.copyWith(longPressSpeed: value));
    await save(state);
  }

  Future<void> updateVolume(int volume) async {
    set(state.copyWith(
        volume: volume < 0
            ? 0
            : volume > 100
                ? 100
                : volume));
    await save(state);
  }

  Future<void> updateMute(bool isMuted) async {
    set(state.copyWith(isMuted: isMuted));
    await save(state);
  }

  Future<void> toggleMute() async {
    set(state.copyWith(isMuted: !state.isMuted));
    save(state);
  }

  Future<void> updateThemeMode(ThemeMode themeMode) async {
    set(state.copyWith(themeMode: themeMode));
    await save(state);
  }

  Future<void> updateLanguage(String language) async {
    set(state.copyWith(language: language));
    await save(state);
  }

  Future<void> toggleAutoResize() async {
    set(state.copyWith(autoResize: !state.autoResize));
    await save(state);
  }

  Future<void> toggleAlwaysPlayFromBeginning() async {
    set(state.copyWith(
        alwaysPlayFromBeginning: !state.alwaysPlayFromBeginning));
    await save(state);
  }

  Future<void> updatePlayerBackend(PlayerBackend backend) async {
    set(state.copyWith(playerBackend: backend));
    await save(state);
  }

  Future<void> updateSortBy(SortBy sortBy) async {
    set(state.copyWith(sortBy: sortBy));
    await save(state);
  }

  Future<void> updateSortOrder(SortOrder sortOrder) async {
    set(state.copyWith(sortOrder: sortOrder));
    await save(state);
  }

  Future<void> updateFolderFirst(bool folderFirst) async {
    set(state.copyWith(folderFirst: folderFirst));
    await save(state);
  }

  Future<void> updateOrientation(ScreenOrientation orientation) async {
    set(state.copyWith(orientation: orientation));
    await save(state);
  }

  Future<void> updateSeekStep(int seconds) async {
    set(state.copyWith(seekStepSeconds: seconds));
    await save(state);
  }

  Future<void> updateSeekStepLarge(int seconds) async {
    set(state.copyWith(seekStepLargeSeconds: seconds));
    await save(state);
  }

  Future<void> togglePureBlackTheme() async {
    set(state.copyWith(pureBlackTheme: !state.pureBlackTheme));
    await save(state);
  }

  Future<void> toggleRememberWindowSize() async {
    set(state.copyWith(rememberWindowSize: !state.rememberWindowSize));
    await save(state);
  }

  Future<void> updateWindowBounds(List<double>? bounds,
      {bool? maximized}) async {
    set(state.copyWith(
      windowBounds: bounds,
      windowMaximized: maximized ?? state.windowMaximized,
    ));
    await save(state);
  }

  @override
  Future<AppState?> load() async {
    logger('Loading AppState');
    try {
      AndroidOptions getAndroidOptions() => const AndroidOptions(
            encryptedSharedPreferences: true,
          );
      final storage = FlutterSecureStorage(aOptions: getAndroidOptions());

      String? appState = await storage.read(key: 'app_state');

      if (appState != null) {
        return AppState.fromJson(json.decode(appState)).copyWith(
          autoPlay: false,
        );
      }
    } catch (e) {
      logger('Error loading AppState: $e');
    }
    return null;
  }

  @override
  Future<void> save(AppState state) async {
    try {
      AndroidOptions getAndroidOptions() => const AndroidOptions(
            encryptedSharedPreferences: true,
          );
      final storage = FlutterSecureStorage(aOptions: getAndroidOptions());

      await storage.write(key: 'app_state', value: json.encode(state.toJson()));
    } catch (e) {
      logger('Error saving AppState: $e');
    }
  }
}

AppStore useAppStore() => create(() => AppStore());
