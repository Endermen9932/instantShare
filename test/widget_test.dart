import 'package:flutter_test/flutter_test.dart';
import 'package:instant_share/app/app.dart';
import 'package:instant_share/app/settings.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    PackageInfo.setMockInitialValues(
      appName: 'InstantShare',
      packageName: 'test',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  for (final size in [const Size(390, 844), const Size(1280, 800)]) {
    testWidgets('all tabs render without layout errors at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final settings = await AppSettings.load();
      await tester.pumpWidget(InstantShareApp(settings: settings));
      await tester.pumpAndSettle();
      expect(find.text('Übertragung starten'), findsOneWidget);

      await tester.tap(find.text('Schnell').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('12 Codes/s'), findsOneWidget);

      await tester.tap(find.text('Empfangen').last);
      await tester.pumpAndSettle();
      expect(find.text('Kamera starten'), findsOneWidget);

      await tester.tap(find.text('Einstellungen').last);
      await tester.pumpAndSettle();
      expect(find.text('Standard-Geschwindigkeit'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Lizenzen'), 300);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
