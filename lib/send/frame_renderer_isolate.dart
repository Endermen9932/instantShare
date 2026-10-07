import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:qr/qr.dart';

import '../core/fountain.dart';
import 'frame_renderer.dart';

Future<FrameRenderer> startRenderer(Uint8List container, int transferId) =>
    _IsolateRenderer.spawn(container, transferId);

class _IsolateRenderer implements FrameRenderer {
  _IsolateRenderer._(this._isolate, this._replies);

  static Future<_IsolateRenderer> spawn(
    Uint8List container,
    int transferId,
  ) async {
    final replies = ReceivePort();
    final isolate = await Isolate.spawn(_worker, (
      replies.sendPort,
      TransferableTypedData.fromList([container]),
      transferId,
    ), debugName: 'qr-frames');
    final renderer = _IsolateRenderer._(isolate, replies);
    final ready = Completer<void>();
    replies.listen((message) {
      if (message is SendPort) {
        renderer._requests = message;
        ready.complete();
        return;
      }
      final (id, size, version, data) =
          message as (int, int, int, TransferableTypedData);
      renderer._pending
          .remove(id)
          ?.complete(QrMatrix(size, data.materialize().asUint8List(), version));
    });
    await ready.future;
    return renderer;
  }

  final Isolate _isolate;
  final ReceivePort _replies;
  late SendPort _requests;
  final Map<int, Completer<QrMatrix>> _pending = {};
  int _nextId = 0;
  bool _disposed = false;

  @override
  Future<QrMatrix> render(int seq, int count, QrErrorCorrectLevel ecc) {
    if (_disposed) return Completer<QrMatrix>().future;
    final id = _nextId++;
    final completer = Completer<QrMatrix>();
    _pending[id] = completer;
    _requests.send((id, seq, count, ecc.index));
    return completer.future;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _isolate.kill(priority: Isolate.immediate);
    _replies.close();
    _pending.clear();
  }
}

void _worker((SendPort, TransferableTypedData, int) args) {
  final (replies, data, transferId) = args;
  final encoder = FountainEncoder(
    transferId,
    data.materialize().asUint8List(),
  );
  final requests = ReceivePort();
  replies.send(requests.sendPort);
  requests.listen((message) {
    final (id, seq, count, ecc) = message as (int, int, int, int);
    final matrix = renderFrame(
      encoder,
      seq,
      count,
      QrErrorCorrectLevel.values[ecc],
    );
    replies.send((
      id,
      matrix.size,
      matrix.version,
      TransferableTypedData.fromList([matrix.modules]),
    ));
  });
}
