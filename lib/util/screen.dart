import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'platform_info.dart';

/// Keeps the display awake; failures (e.g. no D-Bus session) are harmless.
Future<void> keepScreenOn(bool on) async {
  try {
    await WakelockPlus.toggle(enable: on);
  } on Object {
    // Not essential.
  }
}

/// Full brightness makes codes far easier to read for the receiving camera.
Future<void> boostBrightness(bool on) async {
  if (!PlatformInfo.isMobile) return;
  try {
    if (on) {
      await ScreenBrightness.instance.setApplicationScreenBrightness(1);
    } else {
      await ScreenBrightness.instance.resetApplicationScreenBrightness();
    }
  } on Object {
    // Not essential.
  }
}
