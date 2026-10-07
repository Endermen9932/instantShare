// Renders a transfer as a Y4M video, e.g. to feed Chromium's fake camera:
//   dart run tool/make_test_video.dart <file> <out.y4m> [level] [width]
//       [height] [fps] [repeat] [ocVersion] [ocCodes]
// The video plays the first pass plus some fountain frames, like a sender
// screen filmed by a camera. With level "overclock" several codes are laid
// out side by side.
import 'dart:io';
import 'dart:typed_data';

import 'package:instant_share/core/container.dart';
import 'package:instant_share/core/fountain.dart';
import 'package:instant_share/core/speed.dart';
import 'package:instant_share/send/frame_renderer.dart';

void main(List<String> args) {
  final input = File(args[0]);
  final out = File(args[1]);
  final level = SpeedLevel.byName(args.length > 2 ? args[2] : 'balanced');
  final width = args.length > 3 ? int.parse(args[3]) : 800;
  final height = args.length > 4 ? int.parse(args[4]) : 600;
  final fps = args.length > 5 ? int.parse(args[5]) : 10;
  final repeat = args.length > 6 ? int.parse(args[6]) : 2;
  final overclock = OverclockConfig(
    version: args.length > 7 ? int.parse(args[7]) : 40,
    codesPerScreen: args.length > 8 ? int.parse(args[8]) : 2,
  );
  final profile = level.profile(overclock);

  final container = TransferContainer.build(
    TransferPayload.files([
      PayloadFile(input.uri.pathSegments.last, input.readAsBytesSync()),
    ]),
  );
  final encoder = FountainEncoder(0x1234ABCD, container);
  final perFrame = profile.symbolsPerFrame;
  final codes = profile.codesPerScreen;
  final screens = (encoder.k / (perFrame * codes)).ceil() + 4;

  final sink = out.openSync(mode: FileMode.write);
  sink.writeStringSync('YUV4MPEG2 W$width H$height F$fps:1 Ip A1:1 C420jpeg\n');
  final chromaSize = (width ~/ 2) * (height ~/ 2);
  final chroma = Uint8List(chromaSize)..fillRange(0, chromaSize, 128);
  var seq = 0;
  var version = 0;
  for (var s = 0; s < screens; s++) {
    final y = Uint8List(width * height)..fillRange(0, width * height, 200);
    final cellWidth = width ~/ codes;
    for (var c = 0; c < codes; c++) {
      final matrix = renderFrame(
        encoder,
        seq,
        perFrame,
        profile.errorCorrection,
        fixedMask: profile.fixedMask,
      );
      seq += perFrame;
      version = matrix.version;
      final n = matrix.size + 8;
      final module = ((cellWidth < height ? cellWidth : height) * 0.92 / n).floor();
      final side = module * n;
      final left = c * cellWidth + (cellWidth - side) ~/ 2;
      final top = (height - side) ~/ 2;
      for (var py = 0; py < side; py++) {
        final r = py ~/ module - 4;
        for (var px = 0; px < side; px++) {
          final col = px ~/ module - 4;
          final dark = r >= 0 &&
              col >= 0 &&
              r < matrix.size &&
              col < matrix.size &&
              matrix.modules[r * matrix.size + col] == 1;
          y[(top + py) * width + left + px] = dark ? 20 : 235;
        }
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
  stdout.writeln(
    'screens=$screens codes=$codes k=${encoder.k} '
    'container=${container.length} version=$version symbols/code=$perFrame',
  );
}
