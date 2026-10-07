/// German number formatting without pulling in package:intl.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value < 10 ? 1 : 0;
  return '${value.toStringAsFixed(digits).replaceAll('.', ',')} ${units[unit]}';
}

String formatRate(double bytesPerSecond) =>
    '${formatBytes(bytesPerSecond.round())}/s';

String formatDuration(Duration d) {
  if (d < const Duration(seconds: 1)) return '< 1 s';
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  if (h > 0) return '$h h ${m.toString().padLeft(2, '0')} min';
  if (m > 0) return '$m min ${s.toString().padLeft(2, '0')} s';
  return '$s s';
}

String formatPercent(double fraction) =>
    '${(fraction * 100).clamp(0, 100).toStringAsFixed(0)} %';
