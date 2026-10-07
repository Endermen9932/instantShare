import 'package:dynamic_color/dynamic_color.dart';
import 'package:material_ui/material_ui.dart';

import 'home_shell.dart';
import 'settings.dart';

class InstantShareApp extends StatelessWidget {
  const InstantShareApp({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return SettingsScope(
      settings: settings,
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => DynamicColorBuilder(
          builder: (lightDynamic, darkDynamic) {
            ColorScheme light;
            ColorScheme dark;
            if (settings.dynamicColor &&
                lightDynamic != null &&
                darkDynamic != null) {
              light = lightDynamic.harmonized();
              dark = darkDynamic.harmonized();
            } else {
              light = ColorScheme.fromSeed(seedColor: settings.accentColor);
              dark = ColorScheme.fromSeed(
                seedColor: settings.accentColor,
                brightness: Brightness.dark,
              );
            }
            return MaterialApp(
              title: 'InstantShare',
              debugShowCheckedModeBanner: false,
              themeMode: settings.themeMode,
              theme: buildTheme(light),
              darkTheme: buildTheme(dark),
              home: const HomeShell(),
            );
          },
        ),
      ),
    );
  }
}

ThemeData buildTheme(ColorScheme scheme) {
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(28));
  return base.copyWith(
    // Opt into the latest Material 3 specs instead of the 2023 defaults; the
    // flag is deprecated only because the new look will become the default.
    // ignore: deprecated_member_use
    sliderTheme: const SliderThemeData(year2023: false),
    // ignore: deprecated_member_use
    progressIndicatorTheme: const ProgressIndicatorThemeData(year2023: false),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 56),
        textStyle: base.textTheme.titleMedium,
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: const StadiumBorder(),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    iconButtonTheme: const IconButtonThemeData(
      variant: StyleVariant.material3Expressive,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}
