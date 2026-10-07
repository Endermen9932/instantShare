import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_zxing/flutter_zxing.dart' as zxing;

/// zxing-cpp decoders on several isolates, so a fast phone can decode as
/// many camera frames per second as its camera delivers. Each call scans the
/// whole frame for up to [maxSymbols] codes (overclocked senders show
/// several side by side).
class DecodePool {
  DecodePool._(this._workers, this._replies);

  static const int maxSymbols = 4;

  static Future<DecodePool> start(int size) async {
    final replies = ReceivePort();
    final ready = <SendPort>[];
    final isolates = <Isolate>[];
    final pool = DecodePool._(isolates, replies);
    final allReady = Completer<void>();
    replies.listen((message) {
      if (message is SendPort) {
        ready.add(message);
        if (ready.length == size) allReady.complete();
        return;
      }
      final (id, texts) = message as (int, List<String>);
      pool._pending.remove(id)?.complete(texts);
    });
    for (var i = 0; i < size; i++) {
      isolates.add(
        await Isolate.spawn(_worker, replies.sendPort, debugName: 'qr-decode-$i'),
      );
    }
    await allReady.future;
    pool._ports = ready;
    return pool;
  }

  /// Leaves one core for the UI and camera, at most four decoders.
  static int defaultSize(int processors) => max(1, min(4, processors - 1));

  final List<Isolate> _workers;
  final ReceivePort _replies;
  List<SendPort> _ports = const [];
  final Map<int, Completer<List<String>>> _pending = {};
  int _nextId = 0;
  int _nextWorker = 0;
  bool _closed = false;

  int get size => _ports.length;

  int get inFlight => _pending.length;

  /// Decodes tightly packed pixels in zxing [imageFormat].
  Future<List<String>> decode(
    Uint8List pixels,
    int width,
    int height,
    int imageFormat,
  ) {
    if (_closed) return Future.value(const []);
    final id = _nextId++;
    final completer = Completer<List<String>>();
    _pending[id] = completer;
    _ports[_nextWorker].send((
      id,
      TransferableTypedData.fromList([pixels]),
      width,
      height,
      imageFormat,
    ));
    _nextWorker = (_nextWorker + 1) % _ports.length;
    return completer.future;
  }

  void close() {
    _closed = true;
    for (final isolate in _workers) {
      isolate.kill(priority: Isolate.immediate);
    }
    _replies.close();
    for (final c in _pending.values) {
      if (!c.isCompleted) c.complete(const []);
    }
    _pending.clear();
  }
}

void _worker(SendPort replies) {
  final requests = ReceivePort();
  replies.send(requests.sendPort);
  requests.listen((message) {
    final (id, data, width, height, format) =
        message as (int, TransferableTypedData, int, int, int);
    var texts = const <String>[];
    try {
      final codes = zxing.zx.readBarcodes(
        data.materialize().asUint8List(),
        zxing.DecodeParams(
          imageFormat: format,
          format: zxing.Format.qrCode,
          width: width,
          height: height,
          tryHarder: false,
          tryRotate: false,
          tryInverted: false,
          tryDownscale: true,
          maxNumberOfSymbols: DecodePool.maxSymbols,
          isMultiScan: true,
        ),
      );
      texts = [
        for (final code in codes.codes)
          if (code.isValid && code.text != null) code.text!,
      ];
    } on Object {
      // A bad frame is simply skipped.
    }
    replies.send((id, texts));
  });
}
