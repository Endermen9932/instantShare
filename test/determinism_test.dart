import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:instant_share/core/base45.dart';
import 'package:instant_share/core/crc32.dart';
import 'package:instant_share/core/fountain.dart';

/// Runs on the VM and in the browser (`flutter test --platform chrome`):
/// both must derive identical coefficients or transfers between the app and
/// the web app would silently fail.
void main() {
  test('coefficient stream is identical on every platform', () {
    final out = Uint32List(32);
    var hash = 0;
    for (var local = 1000; local < 1200; local++) {
      coefficientsFor(0xDEADBEEF, local % 7, local, 1000, out);
      hash = Crc32.update(hash, Uint8List.sublistView(out));
    }
    final rng = Mulberry32(0xFFFFFFFF);
    final values = [for (var i = 0; i < 4; i++) rng.next()];
    // ignore: avoid_print
    print('hash=$hash values=$values');
    expect(hash, 1244828303);
    expect(values, [3850105811, 813802916, 3073704848, 4054706436]);
  });

  test('round trip through encoder and decoder', () {
    final data = Uint8List.fromList(List.generate(64 * 1500 + 9, (i) => (i * 31) & 0xFF));
    final enc = FountainEncoder(0x80000001, data);
    final dec = FountainDecoder(transferId: 0x80000001, totalLength: data.length);
    final buf = Uint8List(kSymbolSize);
    var seq = 400; // skip part of the systematic pass
    while (!dec.isComplete) {
      enc.writeSymbol(seq, buf, 0);
      dec.addSymbol(seq, buf, 0);
      seq += seq % 3 == 0 ? 2 : 1;
    }
    expect(dec.result, data);
    expect(Base45.decode(Base45.encode(data)), data);
  });
}
