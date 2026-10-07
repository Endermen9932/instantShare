import 'dart:typed_data';

/// CRC-32 (IEEE 802.3), the same checksum zip and PNG use.
abstract final class Crc32 {
  static final Uint32List _table = () {
    final table = Uint32List(256);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
      }
      table[n] = c;
    }
    return table;
  }();

  static int compute(List<int> bytes, [int start = 0, int? end]) =>
      update(0, bytes, start, end);

  /// Continues a running checksum, so large inputs can be fed in pieces.
  static int update(int crc, List<int> bytes, [int start = 0, int? end]) {
    final stop = end ?? bytes.length;
    var c = crc ^ 0xFFFFFFFF;
    for (var i = start; i < stop; i++) {
      c = _table[(c ^ bytes[i]) & 0xFF] ^ (c >> 8);
    }
    return c ^ 0xFFFFFFFF;
  }
}
