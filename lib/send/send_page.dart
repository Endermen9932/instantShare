import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../app/settings.dart';
import '../core/speed.dart';
import '../util/format.dart';
import '../util/platform_info.dart';
import '../widgets/level_selector.dart';
import '../widgets/page_frame.dart';
import '../widgets/qr_view.dart';
import 'send_item.dart';
import 'transmit_controller.dart';
import 'transmit_page.dart';

class SendPage extends StatefulWidget {
  const SendPage({super.key});

  @override
  State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> {
  final List<SendItem> _items = [];
  SpeedLevel? _level;
  bool _dragging = false;
  bool _preparing = false;

  int get _totalSize => _items.fold(0, (sum, i) => sum + i.size);

  Future<void> _pickFiles() async {
    final List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(dialogTitle: 'Dateien wählen');
    } on PlatformException catch (e) {
      _snack('Dateiauswahl fehlgeschlagen: ${e.message}');
      return;
    }
    final items = <SendItem>[];
    for (final file in picked) {
      items.add(
        FileItem(
          name: file.name,
          size: await file.length() ?? 0,
          read: file.readAsBytes,
        ),
      );
    }
    setState(() => _items.addAll(items));
  }

  Future<void> _onDrop(DropDoneDetails details) async {
    final items = <SendItem>[];
    for (final file in details.files) {
      if (file is DropItemDirectory) continue;
      items.add(
        FileItem(
          name: file.name,
          size: await file.length(),
          read: file.readAsBytes,
        ),
      );
    }
    setState(() {
      _dragging = false;
      _items.addAll(items);
    });
  }

  Future<void> _addText({String initial = ''}) async {
    final text = await showDialog<String>(
      context: context,
      builder: (context) => _TextDialog(initial: initial),
    );
    if (text != null && text.isNotEmpty) {
      setState(() => _items.add(TextItem(text)));
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) {
      _snack('Die Zwischenablage enthält keinen Text.');
      return;
    }
    await _addText(initial: text);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _start() async {
    final settings = SettingsScope.read(context);
    final level = _level ?? settings.defaultLevel;
    final estimate = Duration(
      seconds: (_totalSize / level.bytesPerSecond).ceil(),
    );
    if (estimate > const Duration(minutes: 10)) {
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.schedule_rounded),
          title: const Text('Das dauert eine Weile'),
          content: Text(
            'Auf der Stufe „${level.label}“ braucht ein Durchlauf etwa '
            '${formatDuration(estimate)} (vor Komprimierung). '
            'Trotzdem starten?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Starten'),
            ),
          ],
        ),
      );
      if (go != true) return;
    }

    setState(() => _preparing = true);
    try {
      final container = await buildContainer(
        _items,
        compress: settings.compress,
      );
      final controller = TransmitController(
        container: container,
        level: level,
      );
      await controller.start();
      if (!mounted) {
        controller.dispose();
        return;
      }
      final title = _items.length == 1
          ? _items.single.name
          : '${_items.length} Elemente';
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TransmitPage(
            controller: controller,
            title: title,
            payloadSize: _totalSize,
          ),
        ),
      );
    } on Object catch (e) {
      _snack('Vorbereitung fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  void _showWebAppLink() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.public_rounded),
        title: const Text('Web-App öffnen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Das andere Gerät hat die App nicht? Scanne diesen Code mit der '
              'normalen Kamera-App und öffne die Web-App im Browser – dort '
              'kann es sofort empfangen.',
            ),
            const SizedBox(height: 16),
            const TextQrCode(text: webAppReceiveUrl, size: 240),
            const SizedBox(height: 12),
            SelectableText(webAppUrl, textAlign: TextAlign.center),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    final level = _level ?? settings.defaultLevel;
    final theme = Theme.of(context);
    final canDrop = PlatformInfo.isDesktop || PlatformInfo.isWeb;

    final content = PageFrame(
      title: 'Senden',
      subtitle: 'Dateien oder Text als animierte QR-Codes übertragen – '
          'ohne Netzwerk, ohne Konto.',
      trailing: IconButton.filledTonal(
        tooltip: 'Web-App-Link zeigen',
        onPressed: _showWebAppLink,
        icon: const Icon(Icons.qr_code_rounded),
      ),
      children: [
        Row(
          children: [
            Expanded(
              child: _ActionTile(
                icon: Icons.upload_file_rounded,
                label: 'Dateien',
                onTap: _pickFiles,
                primary: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionTile(
                icon: Icons.notes_rounded,
                label: 'Text',
                onTap: _addText,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionTile(
                icon: Icons.content_paste_rounded,
                label: 'Einfügen',
                onTap: _paste,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_items.isEmpty)
          _EmptyHint(dropEnabled: canDrop, dragging: _dragging)
        else
          _ItemList(
            items: _items,
            dragging: _dragging,
            onRemove: (item) => setState(() => _items.remove(item)),
            onClear: () => setState(_items.clear),
          ),
        const SizedBox(height: 28),
        Text('Geschwindigkeit', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        LevelSelector(
          value: level,
          onChanged: (l) => setState(() => _level = l),
        ),
        const SizedBox(height: 12),
        Text(
          levelDescription(level),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${level.framesPerSecond} Codes/s · bis ${formatRate(level.bytesPerSecond.toDouble())}'
          '${_items.isEmpty ? '' : ' · ca. ${formatDuration(Duration(seconds: (_totalSize / level.bytesPerSecond).ceil()))} pro Durchlauf'}',
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 28),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
          onPressed: _items.isEmpty || _preparing ? null : _start,
          icon: _preparing
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Icon(Icons.send_rounded),
          label: Text(_preparing ? 'Wird vorbereitet …' : 'Übertragung starten'),
        ),
      ],
    );

    if (!canDrop) return content;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: _onDrop,
      child: content,
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = primary ? scheme.primaryContainer : scheme.secondaryContainer;
    final fg = primary ? scheme.onPrimaryContainer : scheme.onSecondaryContainer;
    return Card(
      color: bg,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, size: 32, color: fg),
              const SizedBox(height: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(color: fg),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.dropEnabled, required this.dragging});

  final bool dropEnabled;
  final bool dragging;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      decoration: BoxDecoration(
        color: dragging ? scheme.primaryContainer : scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: dragging ? scheme.primary : scheme.outlineVariant,
          width: dragging ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Icon(
            dropEnabled ? Icons.move_to_inbox_rounded : Icons.inventory_2_outlined,
            size: 40,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          Text(
            dropEnabled
                ? 'Dateien hierher ziehen oder oben auswählen'
                : 'Noch nichts ausgewählt',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ItemList extends StatelessWidget {
  const _ItemList({
    required this.items,
    required this.dragging,
    required this.onRemove,
    required this.onClear,
  });

  final List<SendItem> items;
  final bool dragging;
  final ValueChanged<SendItem> onRemove;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = items.fold(0, (sum, i) => sum + i.size);
    return Card(
      color: dragging ? scheme.primaryContainer : null,
      child: Column(
        children: [
          for (final item in items)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: scheme.tertiaryContainer,
                foregroundColor: scheme.onTertiaryContainer,
                child: Icon(
                  item is TextItem
                      ? Icons.notes_rounded
                      : Icons.insert_drive_file_outlined,
                ),
              ),
              title: Text(
                item is TextItem ? item.text : item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                item is TextItem ? 'Text · ${formatBytes(item.size)}' : formatBytes(item.size),
              ),
              trailing: IconButton(
                tooltip: 'Entfernen',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => onRemove(item),
              ),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${items.length} ${items.length == 1 ? 'Element' : 'Elemente'} · ${formatBytes(total)}',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                TextButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: const Text('Alle entfernen'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TextDialog extends StatefulWidget {
  const _TextDialog({required this.initial});

  final String initial;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Text senden'),
      content: SizedBox(
        width: 480,
        child: TextField(
          controller: _text,
          autofocus: true,
          minLines: 4,
          maxLines: 10,
          decoration: const InputDecoration(
            hintText: 'Nachricht, Link, Passwort …',
            border: OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _text.text),
          child: const Text('Hinzufügen'),
        ),
      ],
    );
  }
}
