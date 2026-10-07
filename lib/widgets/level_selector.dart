import 'package:material_ui/material_ui.dart';

import '../core/speed.dart';

IconData levelIcon(SpeedLevel level) => switch (level) {
  SpeedLevel.fast => Icons.bolt_rounded,
  SpeedLevel.balanced => Icons.balance_rounded,
  SpeedLevel.slow => Icons.hourglass_bottom_rounded,
  SpeedLevel.overclock => Icons.rocket_launch_rounded,
};

String levelDescription(SpeedLevel level) => switch (level) {
  SpeedLevel.fast =>
    'Sehr feine Codes mit den meisten Details, die am schnellsten wechseln. '
        'Für scharfe Displays und gute Kameras.',
  SpeedLevel.balanced =>
    'Mittlere Dichte und Geschwindigkeit. Passt für die meisten Geräte.',
  SpeedLevel.slow =>
    'Grobe Codes, die langsam wechseln. Für schwache Displays, ältere '
        'Geräte und schlechte Kameras.',
  SpeedLevel.overclock =>
    'Reizt Displayauflösung und Kamera-Bildrate aus: bis QR-Version 40, '
        'mehrere Codes gleichzeitig und bis zu 60 Wechsel pro Sekunde. Für '
        'High-End-Geräte – Werte unten feinjustieren.',
};

class LevelSelector extends StatelessWidget {
  const LevelSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.compact = false,
  });

  final SpeedLevel value;
  final ValueChanged<SpeedLevel> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Four labelled segments do not fit on phones: there only the
        // selected one keeps its label, and in very narrow panels none does.
        final allLabels = constraints.maxWidth >= 560;
        final selectedLabel = constraints.maxWidth >= 400;
        return SegmentedButton<SpeedLevel>(
          showSelectedIcon: false,
          segments: [
            for (final level in SpeedLevel.values)
              ButtonSegment(
                value: level,
                tooltip: level.label,
                icon: Icon(levelIcon(level)),
                label: allLabels || (selectedLabel && level == value)
                    ? Text(level.label, maxLines: 1, softWrap: false)
                    : null,
              ),
          ],
          selected: {value},
          onSelectionChanged: (s) => onChanged(s.single),
          style: ButtonStyle(
            visualDensity: compact ? VisualDensity.compact : null,
            minimumSize: WidgetStatePropertyAll(Size(0, compact ? 44 : 52)),
          ),
        );
      },
    );
  }
}
