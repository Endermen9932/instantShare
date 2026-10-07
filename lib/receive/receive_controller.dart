import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/container.dart';
import '../core/fountain.dart';
import '../core/frame.dart';
import '../util/background.dart';

enum ReceiveStatus { waiting, receiving, assembling, done, failed }

/// Collects frames from the scanner and reassembles the transfer.
class ReceiveController extends ChangeNotifier {
  ReceiveController({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  ReceiveStatus _status = ReceiveStatus.waiting;
  ReceiveStatus get status => _status;

  FountainDecoder? _decoder;
  ContainerHeader? _header;
  ContainerHeader? get header => _header;

  TransferPayload? _payload;
  TransferPayload? get payload => _payload;

  String? _error;
  String? get error => _error;

  String? _lastText;
  int _framesRead = 0;
  int _foreignFrames = 0;
  int? _candidateId;
  DateTime? _startedAt;
  DateTime? _lastUseful;

  /// Codes decoded by the scanner that belong to the current transfer.
  int get framesRead => _framesRead;

  double get progress => _decoder?.progress ?? 0;

  int get totalBytes => _header?.bodyLength ?? _decoder?.totalLength ?? 0;

  /// Effective throughput of useful data so far.
  double get bytesPerSecond {
    final start = _startedAt;
    final decoder = _decoder;
    if (start == null || decoder == null) return 0;
    final seconds = _clock().difference(start).inMilliseconds / 1000;
    if (seconds < 1) return 0;
    return decoder.rank * kSymbolSize / seconds;
  }

  Duration? get remaining {
    final decoder = _decoder;
    final rate = bytesPerSecond;
    if (decoder == null || rate <= 0) return null;
    final left = (decoder.k - decoder.rank) * kSymbolSize;
    return Duration(seconds: (left / rate).ceil());
  }

  /// True while frames are arriving; false if nothing new came for a while.
  bool get isFlowing {
    final last = _lastUseful;
    return last != null &&
        _clock().difference(last) < const Duration(seconds: 3);
  }

  /// Feeds one decoded QR text. Cheap for duplicates, which are the norm:
  /// the camera sees each code several times.
  void onText(String text) {
    if (_status == ReceiveStatus.assembling || _status == ReceiveStatus.done) {
      return;
    }
    if (text == _lastText) return;
    _lastText = text;
    final frame = Frame.decode(text);
    if (frame == null) return;

    var decoder = _decoder;
    if (decoder == null || decoder.transferId != frame.transferId ||
        decoder.totalLength != frame.totalLength) {
      if (decoder != null && !_switchTo(frame)) return;
      decoder = _decoder = FountainDecoder(
        transferId: frame.transferId,
        totalLength: frame.totalLength,
      );
      _header = null;
      _error = null;
      _framesRead = 0;
      _startedAt = _clock();
      _status = ReceiveStatus.receiving;
    }
    _foreignFrames = 0;
    _framesRead++;

    var useful = false;
    for (var i = 0; i < frame.symbolCount; i++) {
      useful |= decoder.addSymbol(
        frame.firstSeq + i,
        frame.symbols,
        i * kSymbolSize,
      );
    }
    if (useful) _lastUseful = _clock();

    if (_header == null) _tryHeader(decoder);
    if (decoder.isComplete) {
      _assemble(decoder.result);
    }
    notifyListeners();
  }

  /// A different transfer showed up. Switch only once it clearly replaced the
  /// current one, so a stray code from elsewhere cannot wipe progress.
  bool _switchTo(Frame frame) {
    if (_candidateId != frame.transferId) {
      _candidateId = frame.transferId;
      _foreignFrames = 0;
    }
    _foreignFrames++;
    final decoder = _decoder!;
    final stalled = !isFlowing;
    if (_foreignFrames >= 3 && (stalled || decoder.rank == 0)) {
      _candidateId = null;
      return true;
    }
    return false;
  }

  void _tryHeader(FountainDecoder decoder) {
    // The metadata is small; 1 KiB covers even long lists of file names, and
    // shorter prefixes are retried as more arrives.
    for (final length in [256, 1024, 4096]) {
      final prefix = decoder.prefix(min(length, decoder.totalLength));
      if (prefix == null) return;
      try {
        final header = TransferContainer.tryParseHeader(prefix);
        if (header != null) {
          _header = header;
          return;
        }
      } on ContainerFormatException {
        return;
      }
    }
  }

  Future<void> _assemble(Uint8List data) async {
    _status = ReceiveStatus.assembling;
    notifyListeners();
    try {
      _payload = await runInBackground(() => TransferContainer.parse(data));
      _status = ReceiveStatus.done;
    } on Object catch (e) {
      _error = e is ContainerFormatException ? e.message : e.toString();
      _status = ReceiveStatus.failed;
    }
    notifyListeners();
  }

  /// Drops everything and waits for a new transfer.
  void reset() {
    _decoder = null;
    _header = null;
    _payload = null;
    _error = null;
    _lastText = null;
    _framesRead = 0;
    _startedAt = null;
    _lastUseful = null;
    _status = ReceiveStatus.waiting;
    notifyListeners();
  }
}
