import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:instant_share/core/base45.dart';
import 'package:instant_share/core/compression_web.dart' as web;
import 'package:instant_share/core/compression_io.dart' as io;
import 'package:instant_share/core/container.dart';
import 'package:instant_share/core/crc32.dart';
import 'package:instant_share/core/fountain.dart';
import 'package:instant_share/core/frame.dart';
import 'package:instant_share/core/speed.dart';
import 'package:qr/qr.dart';

Uint8List randomBytes(int n, int seed) {
  final r = Random(seed);
  return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
}

/// Simulates a transfer and returns how many symbols the receiver needed.
int transfer(
  Uint8List data, {
  required double loss,
  int startSeq = 0,
  int seed = 1,
  int perFrame = 7,
}) {
  final id = 0xC0FFEE ^ seed;
  final enc = FountainEncoder(id, data);
  final dec = FountainDecoder(transferId: id, totalLength: data.length);
  final rnd = Random(seed);
  var seq = startSeq;
  var received = 0;
  while (!dec.isComplete) {
    final frame = Uint8List(perFrame * kSymbolSize);
    for (var i = 0; i < perFrame; i++) {
      enc.writeSymbol(seq + i, frame, i * kSymbolSize);
    }
    if (rnd.nextDouble() >= loss) {
      for (var i = 0; i < perFrame; i++) {
        dec.addSymbol(seq + i, frame, i * kSymbolSize);
        received++;
        if (dec.isComplete) break;
      }
    }
    seq += perFrame;
    if (seq - startSeq > dec.k * 20 + 2000) fail('did not converge');
  }
  expect(dec.result, data);
  return received;
}

void main() {
  test('base45 matches RFC 9285 vectors and round trips', () {
    expect(Base45.encode(Uint8List.fromList('AB'.codeUnits)), 'BB8');
    expect(Base45.encode(Uint8List.fromList('Hello!!'.codeUnits)), '%69 VD92EX0');
    expect(Base45.encode(Uint8List.fromList('ietf!'.codeUnits)), 'QED8WEX0');
    expect(String.fromCharCodes(Base45.decode('QED8WEX0')!), 'ietf!');
    expect(Base45.decode('GGW'), isNull); // 65536 overflows
    expect(Base45.decode('a'), isNull);
    for (var n = 0; n < 50; n++) {
      final b = randomBytes(n, n);
      expect(Base45.decode(Base45.encode(b)), b);
      expect(Base45.encode(b).length, Base45.encodedLength(n));
    }
  });

  test('pure Dart and zlib deflate are interchangeable', () {
    final data = Uint8List.fromList(List.generate(20000, (i) => (i * 7) % 13));
    expect(web.rawInflate(io.rawDeflate(data)), data);
    expect(io.rawInflate(web.rawDeflate(data)), data);
  });

  test('crc32 check value', () {
    expect(Crc32.compute('123456789'.codeUnits), 0xCBF43926);
  });

  test('coefficients are deterministic', () {
    // Golden values: a change here breaks compatibility between app versions.
    expect(Mulberry32(42).next(), 2581720956);
    final out = Uint32List(32);
    coefficientsFor(1234, 0, 5, 1000, out);
    expect(out[0], 1 << 5);
    coefficientsFor(0xDEADBEEF, 3, 2000, 1000, out);
    final first = out.sublist(0, 4);
    coefficientsFor(0xDEADBEEF, 3, 2000, 1000, out);
    expect(out.sublist(0, 4), first);
    expect(out[31] >> 8, 0); // only 1000 columns
    coefficientsFor(1, 0, 7, 3, out);
    expect(out[0], isNonZero);
  });

  test('block layout covers every symbol exactly once', () {
    for (final len in [1, 64, 65, 64 * 1024, 64 * 1025, 64 * 5000 + 3]) {
      final l = BlockLayout(len);
      var next = 0;
      for (var b = 0; b < l.blockCount; b++) {
        expect(l.blockStart(b), next);
        for (var c = 0; c < l.blockSize(b); c++) {
          expect(l.locateSymbol(next), (b, c));
          next++;
        }
        expect(l.blockSize(b), lessThanOrEqualTo(kMaxBlockSymbols));
      }
      expect(next, l.symbolCount);
    }
  });

  test('frame round trip and corruption detection', () {
    final symbols = randomBytes(3 * kSymbolSize, 9);
    final f = Frame(transferId: 0xABCDEF01, totalLength: 999, firstSeq: 77, symbols: symbols);
    final text = f.encode();
    expect(text.length, Frame.encodedLength(3));
    final back = Frame.decode(text)!;
    expect(back.transferId, 0xABCDEF01);
    expect(back.totalLength, 999);
    expect(back.firstSeq, 77);
    expect(back.symbols, symbols);
    final broken = text.replaceRange(40, 41, text[40] == 'A' ? 'B' : 'A');
    expect(Frame.decode(broken), isNull);
    expect(Frame.decode('HELLO WORLD'), isNull);
  });

  test('tiny transfer decodes from a single frame', () {
    expect(transfer(randomBytes(10, 1), loss: 0), lessThanOrEqualTo(7));
  });

  test('lossless systematic transfer needs exactly k symbols', () {
    final data = randomBytes(64 * 300 + 17, 2);
    final k = symbolCountFor(data.length);
    expect(transfer(data, loss: 0, perFrame: 1), k);
  });

  test('lossy transfers converge with small overhead', () {
    for (final (size, loss) in [(5000, 0.3), (64 * 2000, 0.4), (200000, 0.2), (777, 0.5), (300000, 0.6)]) {
      final data = randomBytes(size, size);
      final k = symbolCountFor(size);
      final needed = transfer(data, loss: loss, seed: size);
      // ignore: avoid_print
      print('size=$size k=$k loss=$loss received=$needed overhead=${(needed / k).toStringAsFixed(3)}');
      expect(needed, lessThan(k * 1.1 + 30));
    }
  });

  test('receiver joining after the systematic pass still decodes', () {
    for (final size in [300, 4000, 64 * 1500, 64 * 3000]) {
      final data = randomBytes(size, size + 1);
      final k = symbolCountFor(size);
      final needed = transfer(data, loss: 0.1, startSeq: k + 13, seed: size);
      // ignore: avoid_print
      print('late join size=$size k=$k received=$needed overhead=${(needed / k).toStringAsFixed(3)}');
      expect(needed, lessThan(k * 1.1 + 40));
    }
  });

  test('metadata prefix is available before the transfer completes', () {
    final container = TransferContainer.build(
      TransferPayload.files([PayloadFile('urlaub.png', randomBytes(64 * 3000, 3))]),
    );
    final enc = FountainEncoder(5, container);
    final dec = FountainDecoder(transferId: 5, totalLength: container.length);
    final buf = Uint8List(kSymbolSize);
    var seq = 0;
    ContainerHeader? header;
    while (header == null) {
      enc.writeSymbol(seq, buf, 0);
      dec.addSymbol(seq++, buf, 0);
      final p = dec.prefix(256);
      if (p != null) header = TransferContainer.tryParseHeader(p);
    }
    expect(header.title, 'urlaub.png');
    expect(dec.isComplete, isFalse);
  });

  test('frames fill their QR version', () {
    expect(symbolsForVersion(25, QrErrorCorrectLevel.low), 19);
    expect(symbolsForVersion(40, QrErrorCorrectLevel.low), 44);
    for (final level in SpeedLevel.values) {
      final profile = level.profile(const OverclockConfig());
      final version = QrCode(
        payload: QrPayload()
          ..addAlphaNumeric('Z' * Frame.encodedLength(profile.symbolsPerFrame)),
        errorCorrectLevel: profile.errorCorrection,
      ).typeNumber;
      expect(version, lessThanOrEqualTo(40), reason: level.name);
    }
    final oc = const OverclockConfig(version: 40, framesPerSecond: 20, codesPerScreen: 2).profile;
    expect(oc.bytesPerSecond, 44 * 64 * 40);
  });

  test('container round trip for files and text', () {
    final text = 'Grüße aus der Kamera! ' * 20;
    final t = TransferContainer.parse(TransferContainer.build(TransferPayload.text(text)));
    expect(t.kind, PayloadKind.text);
    expect(t.text, text);

    final files = [
      PayloadFile('../../etc/passwd', Uint8List.fromList(List.filled(1000, 65))),
      PayloadFile('bild.jpg', randomBytes(3000, 5)),
      PayloadFile('leer.txt', Uint8List(0)),
    ];
    final container = TransferContainer.build(TransferPayload.files(files));
    final header = TransferContainer.tryParseHeader(container)!;
    expect(header.files.map((f) => f.$1), ['passwd', 'bild.jpg', 'leer.txt']);
    expect(header.title, '3 Dateien');
    final back = TransferContainer.parse(container);
    expect(back.files.length, 3);
    expect(back.files[1].bytes, files[1].bytes);
    expect(back.files[0].bytes, files[0].bytes);
    expect(back.files[2].bytes, isEmpty);

    final corrupt = Uint8List.fromList(container);
    corrupt[corrupt.length - 5] ^= 0xFF;
    expect(() => TransferContainer.parse(corrupt), throwsA(isA<ContainerFormatException>()));
  });
}
