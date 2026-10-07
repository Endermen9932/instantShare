import 'package:material_ui/material_ui.dart';

import 'app/app.dart';
import 'app/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();
  runApp(InstantShareApp(settings: settings));
}
