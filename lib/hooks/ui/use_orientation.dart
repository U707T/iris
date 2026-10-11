import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_app_store.dart';

void useOrientation() {
  final context = useContext();
  final orientation =
      useAppStore().select(context, (state) => state.orientation);

  // ignore: no_leading_underscores_for_local_identifiers
  void _setOrientation(ScreenOrientation orientation) {
    if (Platform.isAndroid || Platform.isIOS) {
      switch (orientation) {
        case ScreenOrientation.device:
          SystemChrome.setPreferredOrientations([]);
          break;
        case ScreenOrientation.landscape:
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
          break;
        case ScreenOrientation.portrait:
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
          ]);
          break;
      }
    }
  }

  useEffect(() {
    _setOrientation(orientation);
    return () => SystemChrome.setPreferredOrientations([]);
  }, []);

  useEffect(() {
    _setOrientation(orientation);
    return;
  }, [orientation]);
}
