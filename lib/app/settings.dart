import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/speed.dart';
import '../util/platform_info.dart';

enum CameraQuality {
  medium('480p'),
  high('720p'),
  veryHigh('1080p'),
  ultraHigh('4K');

  const CameraQuality(this.label);

  final String label;
}

/// Accent colours offered when dynamic colour is off or unavailable.
const List<Color> accentColors = [
  Color(0xFF6750A4),
  Color(0xFF0B6BCB),
  Color(0xFF00897B),
  Color(0xFF2E7D32),
  Color(0xFFF57C00),
  Color(0xFFD81B60),
];

class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs);

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
    return AppSettings._(prefs);
  }

  final SharedPreferencesWithCache _prefs;

  ThemeMode get themeMode => ThemeMode.values.firstWhere(
    (m) => m.name == _prefs.getString('themeMode'),
    orElse: () => ThemeMode.system,
  );
  set themeMode(ThemeMode value) => _set('themeMode', value.name);

  bool get dynamicColor => _prefs.getBool('dynamicColor') ?? true;
  set dynamicColor(bool value) => _set('dynamicColor', value);

  Color get accentColor => Color(_prefs.getInt('accent') ?? 0xFF0B6BCB);
  set accentColor(Color value) => _set('accent', value.toARGB32());

  SpeedLevel get defaultLevel => SpeedLevel.byName(_prefs.getString('level'));
  set defaultLevel(SpeedLevel value) => _set('level', value.name);

  OverclockConfig get overclock => OverclockConfig(
    version: _prefs.getInt('ocVersion') ?? 40,
    framesPerSecond: _prefs.getInt('ocFps') ?? 20,
    codesPerScreen: _prefs.getInt('ocCodes') ?? 2,
  );
  set overclock(OverclockConfig value) {
    _prefs.setInt('ocVersion', value.version);
    _prefs.setInt('ocFps', value.framesPerSecond);
    _set('ocCodes', value.codesPerScreen);
  }

  /// Parameters for [level], resolving overclock from the stored tuning.
  TransferProfile profileFor(SpeedLevel level) => level.profile(overclock);

  bool get compress => _prefs.getBool('compress') ?? true;
  set compress(bool value) => _set('compress', value);

  /// Turn the screen to full brightness while sending (mobile only).
  bool get boostBrightness => _prefs.getBool('boostBrightness') ?? true;
  set boostBrightness(bool value) => _set('boostBrightness', value);

  CameraQuality get cameraQuality => CameraQuality.values.firstWhere(
    (q) => q.name == _prefs.getString('cameraQuality'),
    orElse: () =>
        PlatformInfo.isMobile ? CameraQuality.veryHigh : CameraQuality.high,
  );
  set cameraQuality(CameraQuality value) => _set('cameraQuality', value.name);

  /// Requested camera frame rate; 60 helps with overclocked senders on
  /// phones whose camera supports it.
  int get cameraFps => _prefs.getInt('cameraFps') ?? 30;
  set cameraFps(int value) => _set('cameraFps', value);

  /// Target folder for received files on desktop; null means the default.
  String? get saveDirectory => _prefs.getString('saveDirectory');
  set saveDirectory(String? value) => _set('saveDirectory', value);

  void _set(String key, Object? value) {
    switch (value) {
      case null:
        _prefs.remove(key);
      case final String v:
        _prefs.setString(key, v);
      case final bool v:
        _prefs.setBool(key, v);
      case final int v:
        _prefs.setInt(key, v);
    }
    notifyListeners();
  }
}

class SettingsScope extends InheritedNotifier<AppSettings> {
  const SettingsScope({
    super.key,
    required AppSettings settings,
    required super.child,
  }) : super(notifier: settings);

  static AppSettings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsScope>()!.notifier!;

  /// Access without subscribing to changes, e.g. from callbacks.
  static AppSettings read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SettingsScope>()!.notifier!;
}
