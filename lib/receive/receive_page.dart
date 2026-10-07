import 'package:material_ui/material_ui.dart';

import '../util/platform_info.dart';
import '../widgets/page_frame.dart';
import 'scan_page.dart';

class ReceivePage extends StatelessWidget {
  const ReceivePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return PageFrame(
      title: 'Empfangen',
      subtitle: 'Scanne die animierten QR-Codes eines anderen Geräts.',
      children: [
        Card(
          color: scheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(36),
                  ),
                  child: Icon(
                    Icons.qr_code_scanner_rounded,
                    size: 64,
                    color: scheme.onPrimary,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Bereit zum Empfangen',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Die Reihenfolge ist egal und verpasste Codes werden '
                  'automatisch durch neue ersetzt – einfach draufhalten, '
                  'bis der Balken voll ist.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(240, 64),
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const ScanPage()),
                  ),
                  icon: const Icon(Icons.photo_camera_rounded),
                  label: const Text('Kamera starten'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tipps', style: theme.textTheme.titleMedium),
                const _Tip(
                  Icons.brightness_high_rounded,
                  'Helligkeit am Sender hochdrehen, Spiegelungen vermeiden.',
                ),
                const _Tip(
                  Icons.crop_free_rounded,
                  'Abstand so wählen, dass der Code den Rahmen gut ausfüllt.',
                ),
                const _Tip(
                  Icons.hourglass_bottom_rounded,
                  'Klappt es nicht, am Sender „Langsam“ wählen – der '
                  'Fortschritt bleibt erhalten.',
                ),
                if (PlatformInfo.isWeb)
                  const _Tip(
                    Icons.lock_outline_rounded,
                    'Die Web-App arbeitet komplett im Browser. Es werden '
                    'keine Daten hochgeladen.',
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(text),
    );
  }
}
