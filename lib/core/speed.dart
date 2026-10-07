import 'package:qr/qr.dart';

import 'fountain.dart';
import 'frame.dart';

/// How a sender paints codes: density, error correction and pace.
class TransferProfile {
  const TransferProfile({
    required this.symbolsPerFrame,
    required this.errorCorrection,
    required this.framesPerSecond,
    this.codesPerScreen = 1,
    this.fixedMask = false,
  });

  /// Fountain symbols per QR code; decides the QR version.
  final int symbolsPerFrame;
  final QrErrorCorrectLevel errorCorrection;

  /// Screen changes per second.
  final int framesPerSecond;

  /// Codes shown side by side on each screen.
  final int codesPerScreen;

  /// Skip the eight-way mask search. Quality is barely affected for random
  /// data, and it makes dense codes about eight times cheaper to render.
  final bool fixedMask;

  Duration get frameInterval =>
      Duration(microseconds: 1000000 ~/ framesPerSecond);

  int get codesPerSecond => framesPerSecond * codesPerScreen;

  /// Raw payload throughput in bytes per second, before compression.
  int get bytesPerSecond => symbolsPerFrame * kSymbolSize * codesPerSecond;

  @override
  bool operator ==(Object other) =>
      other is TransferProfile &&
      other.symbolsPerFrame == symbolsPerFrame &&
      other.errorCorrection == errorCorrection &&
      other.framesPerSecond == framesPerSecond &&
      other.codesPerScreen == codesPerScreen &&
      other.fixedMask == fixedMask;

  @override
  int get hashCode => Object.hash(
    symbolsPerFrame,
    errorCorrection,
    framesPerSecond,
    codesPerScreen,
    fixedMask,
  );
}

///   fast      19 symbols, QR version 25 (117 modules), 12 codes/s
///   balanced   8 symbols, QR version 18 (89 modules),   7 codes/s
///   slow       2 symbols, QR version 10 (57 modules),   4 codes/s
///   overclock  user-tuned, up to version 40 (177 modules), several codes
///              per screen, up to 60 screens/s
enum SpeedLevel {
  /// Dense codes that change fast; needs a sharp screen and a good camera.
  fast(
    label: 'Schnell',
    preset: TransferProfile(
      symbolsPerFrame: 19,
      errorCorrection: QrErrorCorrectLevel.low,
      framesPerSecond: 12,
    ),
  ),

  balanced(
    label: 'Ausgewogen',
    preset: TransferProfile(
      symbolsPerFrame: 8,
      errorCorrection: QrErrorCorrectLevel.medium,
      framesPerSecond: 7,
    ),
  ),

  /// Coarse codes that change slowly, for poor displays and weak cameras.
  slow(
    label: 'Langsam',
    preset: TransferProfile(
      symbolsPerFrame: 2,
      errorCorrection: QrErrorCorrectLevel.quartile,
      framesPerSecond: 4,
    ),
  ),

  /// Pushes display resolution and camera frame rate to their limits; the
  /// parameters come from [OverclockConfig].
  overclock(label: 'Overclock');

  const SpeedLevel({required this.label, this.preset});

  final String label;

  /// Fixed parameters; null for [overclock].
  final TransferProfile? preset;

  TransferProfile profile(OverclockConfig overclock) =>
      preset ?? overclock.profile;

  static SpeedLevel byName(String? name) => SpeedLevel.values.firstWhere(
    (l) => l.name == name,
    orElse: () => balanced,
  );
}

/// User-tunable parameters of [SpeedLevel.overclock].
class OverclockConfig {
  const OverclockConfig({
    this.version = 40,
    this.framesPerSecond = 20,
    this.codesPerScreen = 2,
  });

  static const int minVersion = 20;
  static const int maxVersion = 40;
  static const int minFps = 5;
  static const int maxFps = 60;
  static const int maxCodes = 3;

  /// QR version of each code (modules per side: 17 + 4 × version).
  final int version;
  final int framesPerSecond;
  final int codesPerScreen;

  int get modules => 17 + 4 * version;

  int get symbolsPerFrame => symbolsForVersion(version, QrErrorCorrectLevel.low);

  TransferProfile get profile => TransferProfile(
    symbolsPerFrame: symbolsPerFrame,
    errorCorrection: QrErrorCorrectLevel.low,
    framesPerSecond: framesPerSecond,
    codesPerScreen: codesPerScreen,
    fixedMask: true,
  );

  OverclockConfig copyWith({
    int? version,
    int? framesPerSecond,
    int? codesPerScreen,
  }) => OverclockConfig(
    version: version ?? this.version,
    framesPerSecond: framesPerSecond ?? this.framesPerSecond,
    codesPerScreen: codesPerScreen ?? this.codesPerScreen,
  );
}

final Map<(int, QrErrorCorrectLevel), int> _capacityCache = {};

/// Most symbols a frame can carry without exceeding QR [version].
int symbolsForVersion(int version, QrErrorCorrectLevel ecc) =>
    _capacityCache.putIfAbsent((version, ecc), () {
      var best = 1;
      for (var n = 1; n <= 64; n++) {
        try {
          final code = QrCode(
            payload: QrPayload()..addAlphaNumeric('A' * Frame.encodedLength(n)),
            errorCorrectLevel: ecc,
          );
          if (code.typeNumber > version) break;
          best = n;
        } on InputTooLongException {
          break;
        }
      }
      return best;
    });
