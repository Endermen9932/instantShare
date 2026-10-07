// Renders a transfer as a Y4M video, e.g. to feed Chromium's fake camera:
//   dart run tool/make_test_video.dart <file> <out.y4m> [level] [width] [height] [fps] [repeat]
// The video loops the first pass plus some fountain frames, just like a
// sender screen filmed by a camera.
import 'dart:io';
import 'dart:typed_data';

import 'package:instant_share/core/container.dart';
import 'package:instant_share/core/fountain.dart';
import 'package:instant_share/core/frame.dart';
import 'package:instant_share/core/speed.dart';
import 'package:qr/qr.dart';

void main(List<String> args) {
  final input = File(args[0]);
  final out = File(args[1]);
  final level = SpeedLevel.byName(args.length > 2 ? args[2] : 'balanced');
  final width = args.length > 3 ? int.parse(args[3]) : 800;
  final height = args.length > 4 ? int.parse(args[4]) : 600;
  final fps = args.length > 5 ? int.parse(args[5]) : 10;
  final repeat = args.length > 6 ? int.parse(args[6]) : 2;

  final container = TransferContainer.build(
    TransferPayload.files([
      PayloadFile(input.uri.pathSegments.last, input.readAsBytesSync()),
    ]),
  );
  final encoder = FountainEncoder(0x1234ABCD, container);
  final perFrame = level.symbolsPerFrame;
  final frameCount = (encoder.k / perFrame).ceil() + 6;

  final sink = out.openSync(mode: FileMode.write);
  sink.writeStringSync('YUV4MPEG2 W$width H$height F$fps:1 Ip A1:1 C420jpeg\n');
  final chroma = Uint8List((width ~/ 2) * (height ~/ 2))..fillRange(0, (width ~/ 2) * (height ~/ 2), 128);
  for (var f = 0; f < frameCount; f++) {
    final seq = f * perFrame;
    final symbols = Uint8List(perFrame * kSymbolSize);
    for (var i = 0; i < perFrame; i++) {
      encoder.writeSymbol(seq + i, symbols, i * kSymbolSize);
    }
    final text = Frame(
      transferId: encoder.transferId,
      totalLength: encoder.totalLength,
      firstSeq: seq,
      symbols: symbols,
    ).encode();
    final image = QrImage(QrCode(
      payload: QrPayload()..addAlphaNumeric(text),
      errorCorrectLevel: level.errorCorrection,
    ));
    final n = image.moduleCount + 8;
    final module = (height * 0.85 / n).floor();
    final side = module * n;
    final left = (width - side) ~/ 2;
    final top = (height - side) ~/ 2;
    final y = Uint8List(width * height)..fillRange(0, width * height, 200);
    for (var py = 0; py < side; py++) {
      final r = py ~/ module - 4;
      for (var px = 0; px < side; px++) {
        final c = px ~/ module - 4;
        final dark = r >= 0 && c >= 0 && r < image.moduleCount && c < image.moduleCount && image.isDark(r, c);
        y[(top + py) * width + left + px] = dark ? 20 : 235;
      }
    }
    for (var rep = 0; rep < repeat; rep++) {
      sink.writeStringSync('FRAME\n');
      sink.writeFromSync(y);
      sink.writeFromSync(chroma);
      sink.writeFromSync(chroma);
    }
  }
  sink.closeSync();
  stdout.writeln('frames=$frameCount k=${encoder.k} container=${container.length} version~${QrCode(payload: QrPayload()..addAlphaNumeric('A' * Frame.encodedLength(perFrame)), errorCorrectLevel: level.errorCorrection).typeNumber}');
}
