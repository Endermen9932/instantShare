import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../app/settings.dart';
import 'scanner_web.dart' if (dart.library.io) 'scanner_native.dart' as impl;

enum ScannerState { starting, running, failed, stopped }

/// Camera plus QR decoder for one platform.
abstract class QrScanner {
  factory QrScanner(CameraQuality quality) => impl.createScanner(quality);

  ValueListenable<ScannerState> get state;

  /// Human-readable reason when [state] is [ScannerState.failed].
  String? get error;

  /// Camera frames run through the decoder so far.
  int get framesAnalyzed;

  Future<void> start(void Function(String text) onCode);

  Future<void> stop();

  bool get canSwitchCamera;

  Future<void> switchCamera();

  /// 1.0 when zoom is not supported.
  double get maxZoom;

  Future<void> setZoom(double zoom);

  Widget buildPreview(BuildContext context);

  void dispose();
}
