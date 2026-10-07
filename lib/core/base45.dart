import 'dart:typed_data';

/// Base45 (RFC 9285). Its alphabet is exactly the QR alphanumeric charset, so
/// a QR code can store the result in alphanumeric mode (5.5 bits per char),
/// which gets within ~3% of byte mode while surviving every decoder's text
/// handling unchanged.
abstract final class Base45 {
  static const String alphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ \$%*+-./:';

  static final Int8List _reverse = () {
    final table = Int8List(128)..fillRange(0, 128, -1);
    for (var i = 0; i < alphabet.length; i++) {
      table[alphabet.codeUnitAt(i)] = i;
    }
    return table;
  }();

  /// Number of characters [encode] produces for [byteLength] bytes.
  static int encodedLength(int byteLength) =>
      (byteLength ~/ 2) * 3 + (byteLength.isOdd ? 2 : 0);

  static String encode(Uint8List bytes) {
    final out = Uint8List(encodedLength(bytes.length));
    var o = 0;
    var i = 0;
    for (; i + 1 < bytes.length; i += 2) {
      var n = (bytes[i] << 8) | bytes[i + 1];
      final c = n % 45;
      n ~/= 45;
      final d = n % 45;
      final e = n ~/ 45;
      out[o++] = alphabet.codeUnitAt(c);
      out[o++] = alphabet.codeUnitAt(d);
      out[o++] = alphabet.codeUnitAt(e);
    }
    if (i < bytes.length) {
      final n = bytes[i];
      out[o++] = alphabet.codeUnitAt(n % 45);
      out[o++] = alphabet.codeUnitAt(n ~/ 45);
    }
    return String.fromCharCodes(out);
  }

  /// Returns null when [text] is not valid Base45.
  static Uint8List? decode(String text) {
    final len = text.length;
    if (len % 3 == 1) return null;
    final out = Uint8List((len ~/ 3) * 2 + (len % 3 == 2 ? 1 : 0));
    var o = 0;
    var i = 0;
    for (; i + 2 < len; i += 3) {
      final c = _value(text.codeUnitAt(i));
      final d = _value(text.codeUnitAt(i + 1));
      final e = _value(text.codeUnitAt(i + 2));
      if (c < 0 || d < 0 || e < 0) return null;
      final n = c + d * 45 + e * 2025;
      if (n > 0xFFFF) return null;
      out[o++] = n >> 8;
      out[o++] = n & 0xFF;
    }
    if (i < len) {
      final c = _value(text.codeUnitAt(i));
      final d = _value(text.codeUnitAt(i + 1));
      if (c < 0 || d < 0) return null;
      final n = c + d * 45;
      if (n > 0xFF) return null;
      out[o++] = n;
    }
    return out;
  }

  static int _value(int codeUnit) => codeUnit < 128 ? _reverse[codeUnit] : -1;
}
