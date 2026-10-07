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
  bool failed = false;
}

/// Drives the QR animation: keeps frames rendered ahead and swaps them in at
/// the pace of the current [TransferProfile], one or more codes per screen.
///
/// Sequence numbers only ever grow. The first `k` symbols are the file itself,
/// everything after that are fountain symbols, so the animation can run as
/// long as the receiver needs and any frame it catches is useful.
class TransmitController extends ChangeNotifier {
  TransmitController({
    required this.container,
    required this._level,
    required this._profile,
  }) : transferId = _randomId(),
       k = symbolCountFor(container.length);

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

  TransferProfile _profile;
  TransferProfile get profile => _profile;

  bool _paused = false;
  bool get paused => _paused;

  List<ui.Image> _images = const [];

  /// The codes currently on screen.
  List<ui.Image> get images => _images;

  int _qrVersion = 0;
  int get qrVersion => _qrVersion;

  int _framesShown = 0;
  int get framesShown => _framesShown;

  int _sentSymbols = 0;

  /// Share of the data shown at least once (the systematic pass).
  double get firstPassProgress => min(1, _sentSymbols / k);

  bool get firstPassDone => _sentSymbols >= k;

  /// Time one pass over the data takes with the current profile.
  Duration get passDuration => Duration(
    milliseconds: (k / (_profile.symbolsPerFrame * _profile.codesPerSecond) * 1000)
        .ceil(),
  );

  int get _lookahead => max(4, _profile.codesPerScreen * 3);

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
      final frame = _PendingFrame(_nextSeq, _profile.symbolsPerFrame);
      _nextSeq += frame.count;
      _queue.add(frame);
      renderer
          .render(
            frame.seq,
            frame.count,
            _profile.errorCorrection,
            fixedMask: _profile.fixedMask,
          )
          .then((matrix) async {
            final image = await qrMatrixToImage(matrix);
            if (frame.discarded || _disposed) {
              image.dispose();
            } else {
              frame.image = image;
              frame.version = matrix.version;
            }
          })
          .catchError((Object _) {
            frame.failed = true;
          });
    }
  }

  /// Called every vsync by the page's ticker.
  void tick(Duration elapsed) {
    if (_paused || _disposed) return;
    // The fountain code does not need any particular frame: drop failures.
    while (_queue.isNotEmpty && _queue.first.failed) {
      _queue.removeFirst();
    }
    _fill();
    final last = _lastSwitch;
    final interval = _profile.frameInterval;
    // A little slack so a 60 Hz display does not skip a whole vsync.
    final slack = Duration(microseconds: min(4000, interval.inMicroseconds ~/ 4));
    if (last != null && elapsed - last < interval - slack) return;
    final need = _profile.codesPerScreen;
    if (_queue.length < need) return;
    final next = _queue.take(need).toList();
    if (next.any((f) => f.image == null || f.failed)) return;
    for (var i = 0; i < need; i++) {
      _queue.removeFirst();
    }
    for (final image in _images) {
      image.dispose();
    }
    _images = [for (final f in next) f.image!];
    _qrVersion = next.first.version;
    _framesShown++;
    _sentSymbols = max(_sentSymbols, next.last.seq + next.last.count);
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
  void setProfile(SpeedLevel level, TransferProfile profile) {
    if (level == _level && profile == _profile) return;
    _level = level;
    final densityChanged =
        profile.symbolsPerFrame != _profile.symbolsPerFrame ||
        profile.errorCorrection != _profile.errorCorrection ||
        profile.fixedMask != _profile.fixedMask;
    _profile = profile;
    if (densityChanged) {
      if (_queue.isNotEmpty) _nextSeq = _queue.first.seq;
      for (final frame in _queue) {
        frame.discarded = true;
        frame.image?.dispose();
      }
      _queue.clear();
    }
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
    for (final image in _images) {
      image.dispose();
    }
    _images = const [];
    super.dispose();
  }
}
