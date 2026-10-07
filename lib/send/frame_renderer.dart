import 'dart:typed_data';

import 'package:qr/qr.dart';

import '../core/fountain.dart';
import '../core/frame.dart';
import 'frame_renderer_inline.dart'
    if (dart.library.io) 'frame_renderer_isolate.dart'
    as impl;

/// Dark/light modules of one QR code, without quiet zone.
class QrMatrix {
  const QrMatrix(this.size, this.modules, this.version);

  final int size;

  /// size × size bytes, 1 for dark.
  final Uint8List modules;
  final int version;

  factory QrMatrix.fromCode(QrCode code) {
    final image = QrImage(code);
    final n = image.moduleCount;
    final modules = Uint8List(n * n);
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        if (image.isDark(r, c)) modules[r * n + c] = 1;
      }
    }
    return QrMatrix(n, modules, code.typeNumber);
  }

  /// A plain QR code for arbitrary text, e.g. a link.
  factory QrMatrix.forText(
    String text, {
    QrErrorCorrectLevel ecc = QrErrorCorrectLevel.medium,
  }) => QrMatrix.fromCode(
    QrCode(payload: QrPayload.fromString(text), errorCorrectLevel: ecc),
  );
}

/// Builds the QR code for the frame starting at symbol [seq].
QrMatrix renderFrame(
  FountainEncoder encoder,
  int seq,
  int count,
  QrErrorCorrectLevel ecc,
) {
  final symbols = Uint8List(count * kSymbolSize);
  for (var i = 0; i < count; i++) {
    encoder.writeSymbol(seq + i, symbols, i * kSymbolSize);
  }
  final text = Frame(
    transferId: encoder.transferId,
    totalLength: encoder.totalLength,
    firstSeq: seq,
    symbols: symbols,
  ).encode();
  return QrMatrix.fromCode(
    QrCode(
      payload: QrPayload()..addAlphaNumeric(text),
      errorCorrectLevel: ecc,
    ),
  );
}

/// Produces QR frames for one transfer, off the UI thread where possible.
abstract class FrameRenderer {
  static Future<FrameRenderer> start(Uint8List container, int transferId) =>
      impl.startRenderer(container, transferId);

  Future<QrMatrix> render(int seq, int count, QrErrorCorrectLevel ecc);

  void dispose();
}
