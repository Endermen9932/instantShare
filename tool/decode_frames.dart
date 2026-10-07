// Reassembles a transfer from decoded QR texts, one per line:
//   dart run tool/decode_frames.dart <frames.txt> <outDir>
// Used by end-to-end tests that film the sender's screen.
import 'dart:io';

import 'package:instant_share/core/container.dart';
import 'package:instant_share/core/fountain.dart';
import 'package:instant_share/core/frame.dart';

void main(List<String> args) {
  final lines = File(args[0]).readAsLinesSync();
  final outDir = Directory(args[1])..createSync(recursive: true);
  FountainDecoder? decoder;
  var frames = 0;
  for (final line in lines) {
    final frame = Frame.decode(line.trim());
    if (frame == null) continue;
    frames++;
    decoder ??= FountainDecoder(
      transferId: frame.transferId,
      totalLength: frame.totalLength,
    );
    for (var i = 0; i < frame.symbolCount; i++) {
      decoder.addSymbol(frame.firstSeq + i, frame.symbols, i * kSymbolSize);
    }
    if (decoder.isComplete) break;
  }
  if (decoder == null || !decoder.isComplete) {
    stdout.writeln(
      'INCOMPLETE frames=$frames rank=${decoder?.rank} k=${decoder?.k}',
    );
    exitCode = 1;
    return;
  }
  final payload = TransferContainer.parse(decoder.result);
  stdout.writeln(
    'COMPLETE frames=$frames k=${decoder.k} received=${decoder.receivedCount}',
  );
  if (payload.kind == PayloadKind.text) {
    File('${outDir.path}/text.txt').writeAsStringSync(payload.text!);
    stdout.writeln('text ${payload.text!.length} chars');
  } else {
    for (final f in payload.files) {
      File('${outDir.path}/${f.name}').writeAsBytesSync(f.bytes);
      stdout.writeln('file ${f.name} ${f.bytes.length} bytes');
    }
  }
}
