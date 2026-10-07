import 'package:material_ui/material_ui.dart';

import '../receive/receive_page.dart';
import '../send/send_page.dart';
import '../settings/settings_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  // Links like …/instantShare/?empfangen open straight on the receive tab,
  // handy for the QR code that points other devices to the web app.
  int _index =
      Uri.base.queryParameters.containsKey('empfangen') ||
          Uri.base.queryParameters.containsKey('receive')
      ? 1
      : 0;

  static const _destinations = [
    (Icons.send_outlined, Icons.send_rounded, 'Senden'),
    (Icons.qr_code_scanner_outlined, Icons.qr_code_scanner_rounded, 'Empfangen'),
    (Icons.settings_outlined, Icons.settings_rounded, 'Einstellungen'),
  ];

  @override
  Widget build(BuildContext context) {
    final body = IndexedStack(
      index: _index,
      children: const [SendPage(), ReceivePage(), SettingsPage()],
    );
    final width = MediaQuery.sizeOf(context).width;
    if (width < 720) {
      return Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            for (final (icon, selected, label) in _destinations)
              NavigationDestination(
                icon: Icon(icon),
                selectedIcon: Icon(selected),
                label: label,
              ),
          ],
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            groupAlignment: -0.9,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.qr_code_2_rounded,
                  color: scheme.onPrimaryContainer,
                  size: 32,
                ),
              ),
            ),
            destinations: [
              for (final (icon, selected, label) in _destinations)
                NavigationRailDestination(
                  icon: Icon(icon),
                  selectedIcon: Icon(selected),
                  label: Text(label),
                ),
            ],
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}
