import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:camera_desktop/camera_desktop.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_zxing/flutter_zxing.dart' as zxing;

import '../../app/settings.dart';
import '../../util/platform_info.dart';
import 'decode_pool.dart';
import 'scanner.dart';

QrScanner createScanner(CameraQuality quality, int fps) =>
    _NativeScanner(quality, fps);

/// `camera` (CameraX on Android, camera_desktop on Linux/Windows) for the
/// frames, zxing-cpp through FFI on a pool of isolates for decoding.
class _NativeScanner implements QrScanner {
  _NativeScanner(this._quality, this._fps);

  final CameraQuality _quality;
  final int _fps;
  final ValueNotifier<ScannerState> _state = ValueNotifier(
    ScannerState.stopped,
  );

  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  CameraController? _controller;
  void Function(String text)? _onCode;
  DecodePool? _pool;
  int _framesAnalyzed = 0;
  double _maxZoom = 1;
  String? _error;

  @override
  ValueListenable<ScannerState> get state => _state;

  @override
  String? get error => _error;

  @override
  int get framesAnalyzed => _framesAnalyzed;

  @override
  bool get canSwitchCamera => _cameras.length > 1;

  @override
  double get maxZoom => _maxZoom;

  ResolutionPreset get _preset => switch (_quality) {
    CameraQuality.medium => ResolutionPreset.medium,
    CameraQuality.high => ResolutionPreset.high,
    CameraQuality.veryHigh => ResolutionPreset.veryHigh,
    CameraQuality.ultraHigh => ResolutionPreset.ultraHigh,
  };

  @override
  Future<void> start(void Function(String text) onCode) async {
    _onCode = onCode;
    _error = null;
    _state.value = ScannerState.starting;
    try {
      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
        final back = _cameras.indexWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
        );
        _cameraIndex = back < 0 ? 0 : back;
      }
      if (_cameras.isEmpty) {
        _fail('Keine Kamera gefunden.');
        return;
      }
      _pool ??= await DecodePool.start(
        DecodePool.defaultSize(Platform.numberOfProcessors),
      );
      final controller = CameraController(
        _cameras[_cameraIndex],
        _preset,
        enableAudio: false,
        // Only ask for more than the default where a camera may deliver it.
        fps: PlatformInfo.isAndroid && _fps > 30 ? _fps : null,
        imageFormatGroup: PlatformInfo.isAndroid
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888,
      );
      _controller = controller;
      await controller.initialize();
      if (PlatformInfo.isLinux) {
        // Linux mirrors frames natively; un-mirror them for the decoder and
        // mirror only the preview (see buildPreview).
        try {
          await CameraDesktopPlugin().setMirror(controller.cameraId, false);
        } on Object {
          // Older backends: zxing also reads mirrored codes, just slower.
        }
      }
      if (PlatformInfo.isMobile) {
        try {
          _maxZoom = (await controller.getMaxZoomLevel()).clamp(1, 8);
        } on CameraException {
          _maxZoom = 1;
        }
      }
      await controller.startImageStream(_onFrame);
      _state.value = ScannerState.running;
    } on CameraException catch (e) {
      _fail(_describe(e));
    } on Object catch (e) {
      _fail('Kamera konnte nicht gestartet werden: $e');
    }
  }

  void _fail(String message) {
    _error = message;
    _state.value = ScannerState.failed;
  }

  String _describe(CameraException e) => switch (e.code) {
    'CameraAccessDenied' ||
    'CameraAccessDeniedWithoutPrompt' ||
    'cameraPermission' => 'Kein Zugriff auf die Kamera. Bitte erlaube den '
        'Kamerazugriff in den Einstellungen.',
    'CameraAccessRestricted' => 'Der Kamerazugriff ist eingeschränkt.',
    _ => 'Kamerafehler: ${e.description ?? e.code}',
  };

  void _onFrame(CameraImage image) {
    final pool = _pool;
    // Drop frames while every decoder is busy; the fountain code needs no
    // particular frame, only as many as possible.
    if (pool == null || pool.inFlight >= pool.size) return;
    final format = zxing.cameraImageFormat(image);
    if (format == zxing.ImageFormat.none) return;
    zxing.convertImage(image).then((pixels) async {
      if (pixels.isEmpty) return;
      final texts = await pool.decode(
        pixels,
        image.width,
        image.height,
        format,
      );
      _framesAnalyzed++;
      for (final text in texts) {
        _onCode?.call(text);
      }
    });
  }

  @override
  Future<void> stop() async {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      try {
        if (controller.value.isStreamingImages) {
          await controller.stopImageStream();
        }
      } on Object {
        // Disposing below releases the stream anyway.
      }
      await controller.dispose();
    }
    if (_state.value != ScannerState.failed) _state.value = ScannerState.stopped;
  }

  @override
  Future<void> switchCamera() async {
    if (!canSwitchCamera) return;
    final onCode = _onCode;
    await stop();
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    if (onCode != null) await start(onCode);
  }

  @override
  Future<void> setZoom(double zoom) async {
    try {
      await _controller?.setZoomLevel(zoom.clamp(1, _maxZoom));
    } on CameraException {
      // Ignore: zoom is optional.
    }
  }

  @override
  Widget buildPreview(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }
    final size = controller.value.previewSize ?? const Size(1280, 720);
    final portrait =
        PlatformInfo.isMobile &&
        MediaQuery.orientationOf(context) == Orientation.portrait;
    Widget preview = CameraPreview(controller);
    if (PlatformInfo.isLinux) {
      preview = Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(-1, 1, 1),
        child: preview,
      );
    }
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: portrait ? size.height : size.width,
          height: portrait ? size.width : size.height,
          child: preview,
        ),
      ),
    );
  }

  @override
  void dispose() {
    stop().whenComplete(() {
      _pool?.close();
      _pool = null;
    });
    _state.dispose();
  }
}
