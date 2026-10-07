import 'package:qr/qr.dart';

/// Trade-off between throughput and how forgiving the codes are.
///   fast      18 symbols, QR version 25 (117 modules), 12 codes/s
///   balanced   8 symbols, QR version 18 (89 modules),   7 codes/s
///   slow       2 symbols, QR version 10 (57 modules),   4 codes/s
enum SpeedLevel {
  /// Dense codes that change fast; needs a sharp screen and a good camera.
  fast(
    label: 'Schnell',
    symbolsPerFrame: 18,
    errorCorrection: QrErrorCorrectLevel.low,
    framesPerSecond: 12,
  ),

  balanced(
    label: 'Ausgewogen',
    symbolsPerFrame: 8,
    errorCorrection: QrErrorCorrectLevel.medium,
    framesPerSecond: 7,
  ),

  /// Coarse codes that change slowly, for poor displays and weak cameras.
  slow(
    label: 'Langsam',
    symbolsPerFrame: 2,
    errorCorrection: QrErrorCorrectLevel.quartile,
    framesPerSecond: 4,
  );

  const SpeedLevel({
    required this.label,
    required this.symbolsPerFrame,
    required this.errorCorrection,
    required this.framesPerSecond,
  });

  final String label;
  final int symbolsPerFrame;
  final QrErrorCorrectLevel errorCorrection;
  final int framesPerSecond;

  Duration get frameInterval =>
      Duration(microseconds: 1000000 ~/ framesPerSecond);

  /// Raw payload throughput in bytes per second, before compression.
  int get bytesPerSecond => symbolsPerFrame * 64 * framesPerSecond;

  static SpeedLevel byName(String? name) =>
      SpeedLevel.values.firstWhere((l) => l.name == name, orElse: () => balanced);
}
