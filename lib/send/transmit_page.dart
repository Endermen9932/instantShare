import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../app/settings.dart';
import '../core/speed.dart';
import '../util/format.dart';
import '../util/screen.dart';
import '../widgets/level_selector.dart';
import '../widgets/overclock_tuner.dart';
import '../widgets/qr_view.dart';
import 'transmit_controller.dart';

/// Shows the animated QR codes until the user stops.
class TransmitPage extends StatefulWidget {
  const TransmitPage({
    super.key,
    required this.controller,
    required this.title,
    required this.payloadSize,
  });

  final TransmitController controller;
  final String title;

  /// Size of the original content, before compression.
  final int payloadSize;

  @override
  State<TransmitPage> createState() => _TransmitPageState();
}

class _TransmitPageState extends State<TransmitPage>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  bool _fullscreen = false;
  final ValueNotifier<int> _pixelsPerModule = ValueNotifier(0);

  TransmitController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_controller.tick)..start();
    keepScreenOn(true);
    if (SettingsScope.read(context).boostBrightness) boostBrightness(true);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _pixelsPerModule.dispose();
    _controller.dispose();
    keepScreenOn(false);
    boostBrightness(false);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _setFullscreen(bool value) {
    setState(() => _fullscreen = value);
    SystemChrome.setEnabledSystemUIMode(
      value ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  @override
  Widget build(BuildContext context) {
    final qr = _QrArea(
      controller: _controller,
      pixelsPerModule: _pixelsPerModule,
    );
    if (_fullscreen) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _setFullscreen(false),
          child: SafeArea(child: Padding(padding: const EdgeInsets.all(8), child: qr)),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Vollbild',
            icon: const Icon(Icons.fullscreen_rounded),
            onPressed: () => _setFullscreen(true),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide =
                constraints.maxWidth > 720 &&
                constraints.maxWidth > constraints.maxHeight * 1.1;
            final panel = _ControlPanel(
              controller: _controller,
              payloadSize: widget.payloadSize,
              pixelsPerModule: _pixelsPerModule,
            );
            final qrCard = Padding(
              padding: const EdgeInsets.all(12),
              child: Card(
                color: Colors.white,
                child: Padding(padding: const EdgeInsets.all(8), child: qr),
              ),
            );
            if (wide) {
              return Row(
                children: [
                  Expanded(child: qrCard),
                  SizedBox(
                    width: 380,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(4, 12, 16, 16),
                      child: panel,
                    ),
                  ),
                ],
              );
            }
            return Column(
              children: [
                Expanded(child: qrCard),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: panel,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _QrArea extends StatelessWidget {
  const _QrArea({required this.controller, required this.pixelsPerModule});

  final TransmitController controller;
  final ValueNotifier<int> pixelsPerModule;

  static const double _gap = 12;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) => ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final images = controller.images;
            if (images.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            // Several codes go along the long side of the area.
            final horizontal = constraints.maxWidth >= constraints.maxHeight;
            final n = images.length;
            final cell = horizontal
                ? Size((constraints.maxWidth - _gap * (n - 1)) / n,
                    constraints.maxHeight)
                : Size(constraints.maxWidth,
                    (constraints.maxHeight - _gap * (n - 1)) / n);
            final ppm = (cell.shortestSide * dpr / images.first.width).floor();
            if (ppm != pixelsPerModule.value) {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => pixelsPerModule.value = ppm,
              );
            }
            return Flex(
              direction: horizontal ? Axis.horizontal : Axis.vertical,
              spacing: _gap,
              children: [
                for (final image in images)
                  Expanded(child: QrImageView(image: image)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({
    required this.controller,
    required this.payloadSize,
    required this.pixelsPerModule,
  });

  final TransmitController controller;
  final int payloadSize;
  final ValueNotifier<int> pixelsPerModule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = SettingsScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([controller, pixelsPerModule]),
      builder: (context, _) {
        final level = controller.level;
        final profile = controller.profile;
        final status = controller.firstPassDone
            ? 'Alle Daten gesendet – läuft weiter, bis der Empfänger fertig ist'
            : 'Erster Durchlauf: ${formatPercent(controller.firstPassProgress)}';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(status, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: controller.firstPassDone
                  ? null
                  : controller.firstPassProgress,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(
                  Icons.description_outlined,
                  controller.container.length < payloadSize * 0.9
                      ? '${formatBytes(payloadSize)} → ${formatBytes(controller.container.length)}'
                      : formatBytes(payloadSize),
                ),
                _InfoChip(
                  Icons.qr_code_2_rounded,
                  'QR v${controller.qrVersion}',
                ),
                _InfoChip(
                  Icons.speed_rounded,
                  formatRate(profile.bytesPerSecond.toDouble()),
                ),
                if (pixelsPerModule.value > 0)
                  _InfoChip(
                    Icons.grid_on_rounded,
                    '${pixelsPerModule.value} px/Modul',
                  ),
                _InfoChip(
                  Icons.timer_outlined,
                  'Durchlauf ${formatDuration(controller.passDuration)}',
                ),
                _InfoChip(Icons.filter_frames_outlined, 'Bild ${controller.framesShown}'),
              ],
            ),
            const SizedBox(height: 16),
            LevelSelector(
              value: level,
              onChanged: (l) => controller.setProfile(l, settings.profileFor(l)),
              compact: true,
            ),
            if (level == SpeedLevel.overclock) ...[
              const SizedBox(height: 12),
              OverclockTuner(
                config: settings.overclock,
                dense: true,
                onChanged: (config) {
                  settings.overclock = config;
                  controller.setProfile(SpeedLevel.overclock, config.profile);
                },
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: controller.togglePause,
                    icon: Icon(
                      controller.paused
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                    ),
                    label: Text(controller.paused ? 'Weiter' : 'Pause'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('Beenden'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Halte die Kamera des Empfängers ruhig auf den Code. Klappt es '
              'nicht, wechsle zu einer langsameren Stufe – der Fortschritt '
              'bleibt erhalten.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: scheme.onSecondaryContainer),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: scheme.onSecondaryContainer),
          ),
        ],
      ),
    );
  }
}
