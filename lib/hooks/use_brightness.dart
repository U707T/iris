import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/utils/logger.dart';
import 'package:screen_brightness/screen_brightness.dart';

ValueNotifier<double?> useBrightness(bool isGesture) {
  final brightness = useState<double?>(null);

  useEffect(() {
    try {
      () async {
        if (!isGesture) return;
        brightness.value = await ScreenBrightness.instance.application;
      }();
    } catch (e) {
      logger('Error getting brightness: $e');
    }
    return () => brightness.value = null;
  }, [isGesture]);

  useEffect(() {
    try {
      if (brightness.value != null && isGesture) {
        ScreenBrightness.instance
            .setApplicationScreenBrightness(brightness.value!);
      }
    } catch (e) {
      logger('Error setting brightness: $e');
    }
    return;
  }, [brightness.value]);

  // 退出时重置亮度
  useEffect(
    () => () {
      try {
        ScreenBrightness.instance.resetApplicationScreenBrightness();
      } catch (e) {
        logger('Error resetting brightness: $e');
      }
    },
    [],
  );

  return brightness;
}
