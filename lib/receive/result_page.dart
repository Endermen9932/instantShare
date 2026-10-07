import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/settings.dart';
import '../core/container.dart';
import '../util/format.dart';
import '../util/platform_info.dart';
import '../util/storage.dart';
import '../widgets/page_frame.dart';
import 'scan_page.dart';

class _FileEntry {
  _FileEntry(this.file);

  final PayloadFile file;
  SavedFile? saved;
  String? error;
  bool busy = false;
}

class ResultPage extends StatefulWidget {
  const ResultPage({super.key, required this.payload});

  final TransferPayload payload;

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  late final List<_FileEntry> _files = [
    for (final f in widget.payload.files) _FileEntry(f),
  ];

  @override
  void initState() {
    super.initState();
    if (savesAutomatically && _files.isNotEmpty) _saveAll();
  }

  Future<void> _saveAll() async {
    for (final entry in _files) {
      if (entry.saved == null) await _save(entry);
    }
  }

  Future<void> _save(_FileEntry entry, {bool ask = false}) async {
    setState(() => entry.busy = true);
    try {
      entry.saved = ask
          ? await saveFileAs(entry.file.name, entry.file.bytes)
          : await saveReceivedFile(
              SettingsScope.read(context),
              entry.file.name,
              entry.file.bytes,
            );
      entry.error = null;
    } on Object catch (e) {
      entry.error = '$e';
    }
    if (mounted) setState(() => entry.busy = false);
  }

  Future<void> _share(_FileEntry entry) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(entry.file.bytes, name: entry.file.name)],
        fileNameOverrides: [entry.file.name],
      ),
    );
  }

  Future<void> _open(_FileEntry entry) async {
    final saved = entry.saved;
    if (saved == null || !await openSavedFile(saved)) {
      _snack('Keine App zum Öffnen gefunden.');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _receiveMore() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const ScanPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final payload = widget.payload;
    final isText = payload.kind == PayloadKind.text;
    final summary = isText
        ? 'Textnachricht · ${formatBytes(payload.rawSize)}'
        : '${_files.length} ${_files.length == 1 ? 'Datei' : 'Dateien'} · '
              '${formatBytes(payload.rawSize)}';
    return Scaffold(
      appBar: AppBar(),
      body: PageFrame(
        title: 'Empfangen!',
        subtitle: summary,
        trailing: CircleAvatar(
          radius: 28,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
          child: const Icon(Icons.done_all_rounded, size: 30),
        ),
        children: [
          if (isText) _TextResult(text: payload.text!) else ..._fileSection(),
          const SizedBox(height: 28),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Fertig'),
              ),
              FilledButton.icon(
                onPressed: _receiveMore,
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('Weiter empfangen'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _fileSection() {
    final scheme = Theme.of(context).colorScheme;
    final firstSaved = _files.map((f) => f.saved).nonNulls.firstOrNull;
    return [
      Card(
        child: Column(
          children: [
            for (final entry in _files)
              ListTile(
                contentPadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                leading: CircleAvatar(
                  backgroundColor: scheme.secondaryContainer,
                  foregroundColor: scheme.onSecondaryContainer,
                  child: Icon(_iconFor(entry.file.name)),
                ),
                title: Text(
                  entry.file.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  [
                    formatBytes(entry.file.bytes.length),
                    if (entry.busy) 'wird gespeichert …',
                    if (entry.saved != null && savesAutomatically)
                      'gespeichert in ${entry.saved!.location}',
                    if (entry.error != null) 'Fehler: ${entry.error}',
                  ].join(' · '),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (entry.saved != null && savesAutomatically)
                      IconButton(
                        tooltip: 'Öffnen',
                        onPressed: () => _open(entry),
                        icon: const Icon(Icons.open_in_new_rounded),
                      ),
                    if (!savesAutomatically)
                      IconButton(
                        tooltip: saveActionLabel,
                        onPressed: () => _save(entry),
                        icon: const Icon(Icons.download_rounded),
                      ),
                    PopupMenuButton<String>(
                      onSelected: (action) => switch (action) {
                        'save' => _save(entry, ask: true),
                        'share' => _share(entry),
                        _ => null,
                      },
                      itemBuilder: (context) => [
                        if (savesAutomatically)
                          const PopupMenuItem(
                            value: 'save',
                            child: ListTile(
                              leading: Icon(Icons.save_as_outlined),
                              title: Text('Speichern unter …'),
                            ),
                          ),
                        const PopupMenuItem(
                          value: 'share',
                          child: ListTile(
                            leading: Icon(Icons.share_outlined),
                            title: Text('Teilen'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      if (!savesAutomatically && _files.length > 1)
        FilledButton.tonalIcon(
          onPressed: _saveAll,
          icon: const Icon(Icons.download_for_offline_outlined),
          label: const Text('Alle herunterladen'),
        ),
      if (canOpenFolder && firstSaved != null)
        FilledButton.tonalIcon(
          onPressed: () => openFolder(firstSaved),
          icon: const Icon(Icons.folder_open_rounded),
          label: const Text('Ordner öffnen'),
        ),
    ];
  }

  IconData _iconFor(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return switch (ext) {
      'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' || 'heic' || 'bmp' =>
        Icons.image_outlined,
      'mp4' || 'mov' || 'mkv' || 'webm' => Icons.movie_outlined,
      'mp3' || 'wav' || 'ogg' || 'm4a' || 'flac' => Icons.music_note_outlined,
      'pdf' => Icons.picture_as_pdf_outlined,
      'zip' || 'rar' || '7z' || 'gz' || 'tar' => Icons.folder_zip_outlined,
      'txt' || 'md' => Icons.article_outlined,
      _ => Icons.insert_drive_file_outlined,
    };
  }
}

class _TextResult extends StatelessWidget {
  const _TextResult({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(text.trim());
    final isLink =
        uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        !text.trim().contains(RegExp(r'\s'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SelectableText(
              text,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.tonalIcon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('In die Zwischenablage kopiert')),
                  );
                }
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Kopieren'),
            ),
            if (isLink)
              FilledButton.tonalIcon(
                onPressed: () => launchUrl(uri, mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_browser_rounded),
                label: const Text('Link öffnen'),
              ),
            if (PlatformInfo.isMobile || PlatformInfo.isMobileWeb)
              FilledButton.tonalIcon(
                onPressed: () => SharePlus.instance.share(ShareParams(text: text)),
                icon: const Icon(Icons.share_rounded),
                label: const Text('Teilen'),
              ),
          ],
        ),
      ],
    );
  }
}
