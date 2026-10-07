import 'dart:typed_data';

import 'package:qr/qr.dart';

import '../core/fountain.dart';
import 'frame_renderer.dart';

/// Browsers have no isolates here; frames are small enough to build on the
/// main thread between animation frames.
Future<FrameRenderer> startRenderer(
  Uint8List container,
  int transferId,
) async => _InlineRenderer(FountainEncoder(transferId, container));

class _InlineRenderer implements FrameRenderer {
  _InlineRenderer(this._encoder);

  final FountainEncoder _encoder;

  @override
  Future<QrMatrix> render(
    int seq,
    int count,
    QrErrorCorrectLevel ecc, {
    bool fixedMask = false,
  }) async {
    await Future<void>.delayed(Duration.zero);
    return renderFrame(_encoder, seq, count, ecc, fixedMask: fixedMask);
  }

  @override
  void dispose() {}
}
