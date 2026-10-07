import 'package:material_ui/material_ui.dart';

import '../core/speed.dart';
import '../util/format.dart';

/// Sliders for the overclock parameters with a live throughput estimate.
class OverclockTuner extends StatelessWidget {
  const OverclockTuner({
    super.key,
    required this.config,
    required this.onChanged,
    this.dense = false,
  });

  final OverclockConfig config;
  final ValueChanged<OverclockConfig> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = theme.textTheme.labelLarge;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final profile = config.profile;
    final perCode = profile.symbolsPerFrame * 64;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'QR-Version ${config.version} · ${config.modules}×${config.modules} '
          'Module · ${formatBytes(perCode)} pro Code',
          style: label,
        ),
        Slider(
          value: config.version.toDouble(),
          min: OverclockConfig.minVersion.toDouble(),
          max: OverclockConfig.maxVersion.toDouble(),
          divisions: OverclockConfig.maxVersion - OverclockConfig.minVersion,
          label: 'v${config.version}',
          onChanged: (v) => onChanged(config.copyWith(version: v.round())),
        ),
        Text('${config.framesPerSecond} Wechsel pro Sekunde', style: label),
        Slider(
          value: config.framesPerSecond.toDouble(),
          min: OverclockConfig.minFps.toDouble(),
          max: OverclockConfig.maxFps.toDouble(),
          divisions: OverclockConfig.maxFps - OverclockConfig.minFps,
          label: '${config.framesPerSecond}/s',
          onChanged: (v) =>
              onChanged(config.copyWith(framesPerSecond: v.round())),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(child: Text('Codes gleichzeitig', style: label)),
            SegmentedButton<int>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [
                for (var n = 1; n <= OverclockConfig.maxCodes; n++)
                  ButtonSegment(value: n, label: Text('$n')),
              ],
              selected: {config.codesPerScreen},
              onSelectionChanged: (s) =>
                  onChanged(config.copyWith(codesPerScreen: s.single)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Bis ${formatRate(profile.bytesPerSecond.toDouble())} '
          '(${profile.codesPerSecond} Codes/s)',
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        if (!dense) ...[
          const SizedBox(height: 6),
          Text(
            'Mehrere Codes nutzen die ganze Bildschirmfläche: am Laptop '
            'nebeneinander, am Handy im Hochformat untereinander. Die Kamera '
            'des Empfängers so halten, dass alle Codes im Bild sind (Handy dann '
            'quer). Über ~25 Wechsel/s erwischt die Kamera meist Übergänge – '
            'dann lieber Version oder Codes erhöhen. Klappt es nicht, Werte '
            'senken; der Fortschritt bleibt erhalten.',
            style: muted,
          ),
        ],
      ],
    );
  }
}
