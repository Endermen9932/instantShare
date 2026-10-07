import 'package:flutter/foundation.dart';

/// Platform checks that also work on the web, where dart:io is unavailable.
abstract final class PlatformInfo {
  static bool get isWeb => kIsWeb;

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static bool get isMobile => isAndroid || isIOS;

  static bool get isLinux =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

  static bool get isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  static bool get isMacOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  static bool get isDesktop => isLinux || isWindows || isMacOS;

  /// The browser runs on a phone or tablet.
  static bool get isMobileWeb =>
      kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
}

/// Public address of the web app (GitHub Pages).
const String webAppUrl = 'https://endermen9932.github.io/instantShare/';

/// Opens the web app directly on the receive tab.
const String webAppReceiveUrl = '$webAppUrl?empfangen';
const String repositoryUrl = 'https://github.com/Endermen9932/instantShare';
