import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:web/web.dart' as web;

import '../../app/settings.dart';
import 'scanner.dart';

QrScanner createScanner(CameraQuality quality, int fps) => _WebScanner();

@JS('instantShareScanner')
external _ScannerJs get _scannerJs;

extension type _ScannerJs(JSObject _) implements JSObject {
  external JSPromise<JSString> start(
    web.HTMLVideoElement video,
    JSString? deviceId,
    JSFunction onText,
  );
  external JSPromise<JSAny?> stop();
  external JSPromise<JSString> listCameras();
  external JSNumber framesAnalyzed();
}

/// getUserMedia for the frames, zxing-cpp compiled to WebAssembly for
/// decoding (see web/qr_scanner.js).
class _WebScanner implements QrScanner {
  _WebScanner() {
    _video = web.HTMLVideoElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover'
      ..style.backgroundColor = 'black';
    _viewType = 'instantshare-camera-${_counter++}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) => _video);
  }

  static int _counter = 0;

  late final web.HTMLVideoElement _video;
  late final String _viewType;
  final ValueNotifier<ScannerState> _state = ValueNotifier(
    ScannerState.stopped,
  );
  List<String> _deviceIds = const [];
  String? _currentDevice;
  String? _error;

  @override
  ValueListenable<ScannerState> get state => _state;

  @override
  String? get error => _error;

  @override
  int get framesAnalyzed => _scannerJs.framesAnalyzed().toDartInt;

  @override
  bool get canSwitchCamera => _deviceIds.length > 1;

  @override
  double get maxZoom => 1;

  void Function(String text)? _onCode;

  @override
  Future<void> start(void Function(String text) onCode) async {
    _onCode = onCode;
    _error = null;
    _state.value = ScannerState.starting;
    try {
      final info = await _scannerJs
          .start(
            _video,
            _currentDevice?.toJS,
            ((JSString text) => _onCode?.call(text.toDart)).toJS,
          )
          .toDart;
      final json = jsonDecode(info.toDart) as Map<String, dynamic>;
      _currentDevice = json['deviceId'] as String?;
      // Mirror user-facing cameras (laptop webcams, selfie cams) so aiming
      // feels natural. Only the preview is flipped; decoding uses raw frames.
      _video.style.transform = json['facingMode'] == 'environment'
          ? 'none'
          : 'scaleX(-1)';
      // Labels and the full list are only available after permission.
      final cameras = jsonDecode((await _scannerJs.listCameras().toDart).toDart)
          as List<dynamic>;
      _deviceIds = [
        for (final c in cameras) (c as Map<String, dynamic>)['id'] as String,
      ];
      _state.value = ScannerState.running;
    } on Object catch (e) {
      final text = e.toString();
      _error = text.contains('NotAllowed') || text.contains('Permission')
          ? 'Kein Zugriff auf die Kamera. Bitte erlaube den Kamerazugriff '
                'für diese Seite im Browser.'
          : text.contains('NotFound')
          ? 'Keine Kamera gefunden.'
          : 'Kamera konnte nicht gestartet werden: $text';
      _state.value = ScannerState.failed;
    }
  }

  @override
  Future<void> stop() async {
    await _scannerJs.stop().toDart;
    if (_state.value != ScannerState.failed) _state.value = ScannerState.stopped;
  }

  @override
  Future<void> switchCamera() async {
    if (!canSwitchCamera) return;
    final index = _deviceIds.indexOf(_currentDevice ?? '');
    _currentDevice = _deviceIds[(index + 1) % _deviceIds.length];
    final onCode = _onCode;
    if (onCode != null) await start(onCode);
  }

  @override
  Future<void> setZoom(double zoom) async {}

  @override
  Widget buildPreview(BuildContext context) =>
      HtmlElementView(viewType: _viewType);

  @override
  void dispose() {
    stop();
    _state.dispose();
  }
}
