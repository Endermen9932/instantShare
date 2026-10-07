import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/settings.dart';
import '../util/platform_info.dart';
import '../util/storage.dart';
import '../widgets/level_selector.dart';
import '../widgets/page_frame.dart';
import '../widgets/qr_view.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    final theme = Theme.of(context);
    return PageFrame(
      title: 'Einstellungen',
      children: [
        const _SectionTitle('Darstellung'),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto_rounded),
                      label: Text('System'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode_rounded),
                      label: Text('Hell'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode_rounded),
                      label: Text('Dunkel'),
                    ),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (s) => settings.themeMode = s.single,
                ),
              ),
              if (PlatformInfo.isAndroid || PlatformInfo.isDesktop)
                SwitchListTile(
                  title: const Text('Dynamische Farben'),
                  subtitle: const Text(
                    'Farben aus dem Hintergrundbild bzw. der Systemakzentfarbe',
                  ),
                  value: settings.dynamicColor,
                  onChanged: (v) => settings.dynamicColor = v,
                ),
              ListTile(
                title: const Text('Akzentfarbe'),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final color in accentColors)
                        _ColorDot(
                          color: color,
                          selected:
                              settings.accentColor.toARGB32() ==
                              color.toARGB32(),
                          onTap: () {
                            settings.accentColor = color;
                            settings.dynamicColor = false;
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const _SectionTitle('Senden'),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                title: const Text('Standard-Geschwindigkeit'),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: LevelSelector(
                    value: settings.defaultLevel,
                    onChanged: (l) => settings.defaultLevel = l,
                  ),
                ),
              ),
              SwitchListTile(
                title: const Text('Komprimieren'),
                subtitle: const Text(
                  'Spart bei Text und Dokumenten viel Zeit. Bereits '
                  'komprimierte Dateien werden automatisch unverändert gesendet.',
                ),
                value: settings.compress,
                onChanged: (v) => settings.compress = v,
              ),
              if (PlatformInfo.isMobile)
                SwitchListTile(
                  title: const Text('Volle Helligkeit beim Senden'),
                  value: settings.boostBrightness,
                  onChanged: (v) => settings.boostBrightness = v,
                ),
            ],
          ),
        ),
        const _SectionTitle('Empfangen'),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!PlatformInfo.isWeb)
                ListTile(
                  title: const Text('Kameraauflösung'),
                  subtitle: const Text(
                    'Höher liest feinere Codes, braucht aber mehr Leistung.',
                  ),
                  trailing: DropdownButton<CameraQuality>(
                    value: settings.cameraQuality,
                    underline: const SizedBox.shrink(),
                    borderRadius: BorderRadius.circular(16),
                    items: [
                      for (final q in CameraQuality.values)
                        DropdownMenuItem(value: q, child: Text(q.label)),
                    ],
                    onChanged: (q) {
                      if (q != null) settings.cameraQuality = q;
                    },
                  ),
                ),
              if (PlatformInfo.isAndroid)
                SwitchListTile(
                  title: const Text('60 fps Kamera'),
                  subtitle: const Text(
                    'Für den Overclock-Modus: liest doppelt so viele Bilder '
                    'pro Sekunde, wenn die Kamera es unterstützt.',
                  ),
                  value: settings.cameraFps >= 60,
                  onChanged: (v) => settings.cameraFps = v ? 60 : 30,
                ),
              if (PlatformInfo.isDesktop) const _SaveFolderTile(),
              if (PlatformInfo.isAndroid)
                const ListTile(
                  title: Text('Speicherort'),
                  subtitle: Text('Download/InstantShare'),
                ),
              if (PlatformInfo.isWeb)
                const ListTile(
                  title: Text('Speicherort'),
                  subtitle: Text(
                    'Empfangene Dateien werden über den Browser heruntergeladen.',
                  ),
                ),
            ],
          ),
        ),
        const _SectionTitle('Web-App'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Wrap(
              spacing: 20,
              runSpacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const TextQrCode(text: webAppUrl, size: 140),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Für Geräte ohne App',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Die Web-App kann alles, was die App kann – direkt im '
                        'Browser und ohne Server.',
                      ),
                      const SizedBox(height: 6),
                      TextButton.icon(
                        onPressed: () => launchUrl(Uri.parse(webAppUrl)),
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: const Text(webAppUrl),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const _SectionTitle('Über'),
        Card(
          child: Column(
            children: [
              FutureBuilder(
                future: PackageInfo.fromPlatform(),
                builder: (context, snapshot) => ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('InstantShare'),
                  subtitle: Text(
                    snapshot.hasData ? 'Version ${snapshot.data!.version}' : '',
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.code_rounded),
                title: const Text('Quellcode'),
                subtitle: const Text(repositoryUrl),
                onTap: () => launchUrl(Uri.parse(repositoryUrl)),
              ),
              ListTile(
                leading: const Icon(Icons.gavel_rounded),
                title: const Text('Lizenzen'),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'InstantShare',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 20, 8, 10),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 28,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(selected ? 14 : 22),
          border: selected
              ? Border.all(
                  color: Theme.of(context).colorScheme.onSurface,
                  width: 3,
                )
              : null,
        ),
        child: selected
            ? const Icon(Icons.check_rounded, color: Colors.white)
            : null,
      ),
    );
  }
}

class _SaveFolderTile extends StatelessWidget {
  const _SaveFolderTile();

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    return FutureBuilder(
      future: saveDirectoryFor(settings),
      builder: (context, snapshot) => ListTile(
        title: const Text('Speicherort'),
        subtitle: Text(snapshot.data ?? ''),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (settings.saveDirectory != null)
              IconButton(
                tooltip: 'Zurücksetzen',
                onPressed: () => settings.saveDirectory = null,
                icon: const Icon(Icons.restart_alt_rounded),
              ),
            FilledButton.tonal(
              onPressed: () async {
                final dir = await FilePicker.getDirectoryPath(
                  dialogTitle: 'Speicherort wählen',
                );
                if (dir != null) settings.saveDirectory = dir;
              },
              child: const Text('Ändern'),
            ),
          ],
        ),
      ),
    );
  }
}
