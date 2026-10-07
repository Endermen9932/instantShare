import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../send/frame_renderer.dart';

/// Converts a QR matrix into a 1-pixel-per-module image including the
/// 4-module quiet zone. Drawn with nearest-neighbour scaling it stays sharp
/// at any size, which matters a lot for dense codes.
Future<ui.Image> qrMatrixToImage(QrMatrix matrix, {int quietZone = 4}) {
  final side = matrix.size + quietZone * 2;
  final pixels = Uint8List(side * side * 4)..fillRange(0, side * side * 4, 255);
  for (var r = 0; r < matrix.size; r++) {
    for (var c = 0; c < matrix.size; c++) {
      if (matrix.modules[r * matrix.size + c] == 0) continue;
      final i = ((r + quietZone) * side + c + quietZone) * 4;
      pixels[i] = 0;
      pixels[i + 1] = 0;
      pixels[i + 2] = 0;
    }
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    side,
    side,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// Paints a QR image as large as possible with an integer number of
/// physical pixels per module.
class QrImagePainter extends CustomPainter {
  QrImagePainter(this.image, this.devicePixelRatio);

  final ui.Image image;
  final double devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final n = image.width.toDouble();
    final available = size.shortestSide * devicePixelRatio;
    var scale = (available / n).floorToDouble();
    if (scale < 1) scale = available / n;
    final side = scale * n / devicePixelRatio;
    final left = ((size.width - side) / 2 * devicePixelRatio).roundToDouble() /
        devicePixelRatio;
    final top = ((size.height - side) / 2 * devicePixelRatio).roundToDouble() /
        devicePixelRatio;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, n, n),
      Rect.fromLTWH(left, top, side, side),
      Paint()
        ..filterQuality = FilterQuality.none
        ..isAntiAlias = false,
    );
  }

  @override
  bool shouldRepaint(QrImagePainter old) =>
      old.image != image || old.devicePixelRatio != devicePixelRatio;
}

class QrImageView extends StatelessWidget {
  const QrImageView({super.key, required this.image});

  final ui.Image image;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: QrImagePainter(image, MediaQuery.devicePixelRatioOf(context)),
    size: Size.infinite,
  );
}

/// A static QR code for arbitrary text, e.g. the web app link.
class TextQrCode extends StatefulWidget {
  const TextQrCode({super.key, required this.text, this.size = 220});

  final String text;
  final double size;

  @override
  State<TextQrCode> createState() => _TextQrCodeState();
}

class _TextQrCodeState extends State<TextQrCode> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _build();
  }

  @override
  void didUpdateWidget(TextQrCode old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _build();
  }

  Future<void> _build() async {
    final image = await qrMatrixToImage(QrMatrix.forText(widget.text));
    if (!mounted) {
      image.dispose();
      return;
    }
    setState(() {
      _image?.dispose();
      _image = image;
    });
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return SizedBox.square(
      dimension: widget.size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ColoredBox(
          color: Colors.white,
          child: image == null ? null : QrImageView(image: image),
        ),
      ),
    );
  }
}
