import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../app/settings.dart';
import '../util/format.dart';
import '../util/screen.dart';
import 'receive_controller.dart';
import 'result_page.dart';
import 'scanner/scanner.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> with WidgetsBindingObserver {
  late final QrScanner _scanner;
  final ReceiveController _receiver = ReceiveController();
  Timer? _refresh;
  double _zoom = 1;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    final settings = SettingsScope.read(context);
    _scanner = QrScanner(settings.cameraQuality, fps: settings.cameraFps);
    _scanner.start(_receiver.onText).then((_) {
      if (mounted) setState(() {});
    });
    _receiver.addListener(_onReceiverChanged);
    WidgetsBinding.instance.addObserver(this);
    keepScreenOn(true);
    // Rates and "no new data" hints depend on time, not only on frames.
    _refresh = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => setState(() {}),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        _scanner.stop();
      case AppLifecycleState.resumed:
        if (_scanner.state.value == ScannerState.stopped && !_navigated) {
          _scanner.start(_receiver.onText).then((_) {
            if (mounted) setState(() {});
          });
        }
      default:
        break;
    }
  }

  void _onReceiverChanged() {
    final payload = _receiver.payload;
    if (_receiver.status == ReceiveStatus.done &&
        payload != null &&
        !_navigated) {
      _navigated = true;
      _scanner.stop();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => ResultPage(payload: payload)),
      );
    }
  }

  @override
  void dispose() {
    _refresh?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _receiver.removeListener(_onReceiverChanged);
    _scanner.dispose();
    _receiver.dispose();
    keepScreenOn(false);
    super.dispose();
  }

  Future<void> _retry() async {
    await _scanner.stop();
    await _scanner.start(_receiver.onText);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: ValueListenableBuilder(
              valueListenable: _scanner.state,
              builder: (context, state, _) => switch (state) {
                ScannerState.failed => _CameraError(
                  message: _scanner.error ?? 'Unbekannter Fehler',
                  onRetry: _retry,
                ),
                ScannerState.running => _scanner.buildPreview(context),
                _ => const Center(child: CircularProgressIndicator()),
              },
            ),
          ),
          const Positioned.fill(
            child: IgnorePointer(child: CustomPaint(painter: _ViewfinderPainter())),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton.filledTonal(
                        tooltip: 'Zurück',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const Spacer(),
                      if (_scanner.canSwitchCamera)
                        IconButton.filledTonal(
                          tooltip: 'Kamera wechseln',
                          onPressed: () async {
                            await _scanner.switchCamera();
                            if (mounted) setState(() => _zoom = 1);
                          },
                          icon: const Icon(Icons.cameraswitch_rounded),
                        ),
                    ],
                  ),
                  const Spacer(),
                  if (_scanner.maxZoom > 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.zoom_out_rounded, color: Colors.white),
                          Expanded(
                            child: Slider(
                              value: _zoom,
                              min: 1,
                              max: _scanner.maxZoom,
                              onChanged: (v) {
                                setState(() => _zoom = v);
                                _scanner.setZoom(v);
                              },
                            ),
                          ),
                          const Icon(Icons.zoom_in_rounded, color: Colors.white),
                        ],
                      ),
                    ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: _StatusCard(
                      receiver: _receiver,
                      framesAnalyzed: _scanner.framesAnalyzed,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.receiver, required this.framesAnalyzed});

  final ReceiveController receiver;
  final int framesAnalyzed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final Widget content;
    switch (receiver.status) {
      case ReceiveStatus.waiting:
        content = Row(
          children: [
            const SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Suche nach QR-Codes …', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Richte die Kamera auf den Bildschirm des Senders. '
                    'Analysierte Bilder: $framesAnalyzed',
                    style: muted,
                  ),
                ],
              ),
            ),
          ],
        );
      case ReceiveStatus.receiving || ReceiveStatus.assembling:
        final header = receiver.header;
        final remaining = receiver.remaining;
        final assembling = receiver.status == ReceiveStatus.assembling;
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.downloading_rounded,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    header?.title ?? 'Daten werden empfangen',
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  formatPercent(receiver.progress),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: assembling ? null : receiver.progress,
              minHeight: 8,
            ),
            const SizedBox(height: 10),
            Text(
              assembling
                  ? 'Wird zusammengesetzt …'
                  : [
                      formatBytes(receiver.totalBytes),
                      if (receiver.bytesPerSecond > 0)
                        formatRate(receiver.bytesPerSecond),
                      if (remaining != null) 'noch ${formatDuration(remaining)}',
                      '${receiver.framesRead} Codes',
                    ].join(' · '),
              style: muted,
            ),
            if (!assembling && !receiver.isFlowing) ...[
              const SizedBox(height: 8),
              Text(
                'Gerade kommen keine neuen Daten an. Abstand oder Winkel '
                'ändern – oder am Sender eine langsamere Stufe wählen.',
                style: muted?.copyWith(color: theme.colorScheme.tertiary),
              ),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: receiver.reset,
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Neu beginnen'),
              ),
            ),
          ],
        );
      case ReceiveStatus.failed:
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline_rounded, color: theme.colorScheme.error),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Übertragung fehlerhaft',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(receiver.error ?? '', style: muted),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: receiver.reset,
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Erneut empfangen'),
              ),
            ),
          ],
        );
      case ReceiveStatus.done:
        content = const SizedBox.shrink();
    }
    return Card(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(padding: const EdgeInsets.all(20), child: content),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined, size: 56, color: Colors.white70),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Erneut versuchen'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dims everything outside the centred square that the decoder scans.
class _ViewfinderPainter extends CustomPainter {
  const _ViewfinderPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide * 0.82;
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero).translate(0, -size.height * 0.06),
      width: side,
      height: side,
    );
    final hole = RRect.fromRectAndRadius(rect, const Radius.circular(32));
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(hole),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
    canvas.drawRRect(
      hole,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_ViewfinderPainter oldDelegate) => false;
}
