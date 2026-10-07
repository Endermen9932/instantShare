import 'dart:collection';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../core/fountain.dart';
import '../core/speed.dart';
import '../widgets/qr_view.dart';
import 'frame_renderer.dart';

class _PendingFrame {
  _PendingFrame(this.seq, this.count);

  final int seq;
  final int count;
  ui.Image? image;
  int version = 0;
  bool discarded = false;
}

/// Drives the QR animation: keeps a few frames rendered ahead and swaps them
/// in at the pace of the current [SpeedLevel].
///
/// Sequence numbers only ever grow. The first `k` symbols are the file itself,
/// everything after that are fountain symbols, so the animation can run as
/// long as the receiver needs and any frame it catches is useful.
class TransmitController extends ChangeNotifier {
  TransmitController({required this.container, required this._level})
    : transferId = _randomId(),
      k = symbolCountFor(container.length);

  static const int _lookahead = 4;

  /// 32 random bits built from two halves, which is also exact on the web.
  static int _randomId() {
    final random = Random.secure();
    return (random.nextInt(0x10000) << 16) | random.nextInt(0x10000);
  }

  final Uint8List container;
  final int transferId;
  final int k;

  FrameRenderer? _renderer;
  final ListQueue<_PendingFrame> _queue = ListQueue();
  int _nextSeq = 0;
  bool _disposed = false;

  SpeedLevel _level;
  SpeedLevel get level => _level;

  bool _paused = false;
  bool get paused => _paused;

  ui.Image? _image;
  ui.Image? get image => _image;

  int _qrVersion = 0;
  int get qrVersion => _qrVersion;

  int _framesShown = 0;
  int get framesShown => _framesShown;

  int _sentSymbols = 0;

  /// Share of the data shown at least once (the systematic pass).
  double get firstPassProgress => min(1, _sentSymbols / k);

  bool get firstPassDone => _sentSymbols >= k;

  /// Symbols sent beyond one full copy of the data.
  int get extraSymbols => max(0, _sentSymbols - k);

  /// Time one pass over the data takes at the current level.
  Duration get passDuration => Duration(
    milliseconds:
        (k / (_level.symbolsPerFrame * _level.framesPerSecond) * 1000).ceil(),
  );

  Duration? _lastSwitch;

  Future<void> start() async {
    _renderer = await FrameRenderer.start(container, transferId);
    if (_disposed) {
      _renderer?.dispose();
      return;
    }
    _fill();
  }

  void _fill() {
    final renderer = _renderer;
    if (renderer == null || _disposed) return;
    while (_queue.length < _lookahead) {
      final frame = _PendingFrame(_nextSeq, _level.symbolsPerFrame);
      _nextSeq += frame.count;
      _queue.add(frame);
      renderer
          .render(frame.seq, frame.count, _level.errorCorrection)
          .then((matrix) async {
            final image = await qrMatrixToImage(matrix);
            if (frame.discarded || _disposed) {
              image.dispose();
            } else {
              frame.image = image;
              frame.version = matrix.version;
            }
          });
    }
  }

  /// Called every vsync by the page's ticker.
  void tick(Duration elapsed) {
    if (_paused || _disposed || _queue.isEmpty) return;
    final last = _lastSwitch;
    final interval = _level.frameInterval;
    // A little slack so a 60 Hz display does not skip a whole vsync.
    const slack = Duration(milliseconds: 4);
    if (last != null && elapsed - last < interval - slack) return;
    final next = _queue.first;
    final image = next.image;
    if (image == null) return;
    _queue.removeFirst();
    _image?.dispose();
    _image = image;
    _qrVersion = next.version;
    _framesShown++;
    _sentSymbols = max(_sentSymbols, next.seq + next.count);
    // Keep a steady cadence instead of accumulating vsync rounding.
    _lastSwitch = last != null && elapsed - last < interval * 2
        ? last + interval
        : elapsed;
    _fill();
    notifyListeners();
  }

  void togglePause() {
    _paused = !_paused;
    _lastSwitch = null;
    notifyListeners();
  }

  /// Switches density and pace without restarting: the receiver keeps
  /// everything it already has.
  void setLevel(SpeedLevel level) {
    if (level == _level) return;
    _level = level;
    if (_queue.isNotEmpty) _nextSeq = _queue.first.seq;
    for (final frame in _queue) {
      frame.discarded = true;
      frame.image?.dispose();
    }
    _queue.clear();
    _fill();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _renderer?.dispose();
    for (final frame in _queue) {
      frame.image?.dispose();
    }
    _queue.clear();
    _image?.dispose();
    _image = null;
    super.dispose();
  }
}
