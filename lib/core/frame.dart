import 'dart:typed_data';

import 'base45.dart';
import 'crc32.dart';
import 'fountain.dart';

/// One QR code worth of data.
///
/// Binary layout (big endian), then Base45 encoded:
///   u8  protocol version
///   u32 transfer id
///   u32 total length of the transfer container
///   u32 sequence number of the first symbol
///   n × [kSymbolSize] symbols with consecutive sequence numbers
///   u32 CRC-32 of everything above
class Frame {
  Frame({
    required this.transferId,
    required this.totalLength,
    required this.firstSeq,
    required this.symbols,
  });

  static const int protocolVersion = 1;
  static const int headerSize = 13;
  static const int checksumSize = 4;
  static const int overhead = headerSize + checksumSize;

  final int transferId;
  final int totalLength;
  final int firstSeq;
  final Uint8List symbols;

  int get symbolCount => symbols.length ~/ kSymbolSize;

  /// QR alphanumeric characters needed for a frame with [symbolCount] symbols.
  static int encodedLength(int symbolCount) =>
      Base45.encodedLength(overhead + symbolCount * kSymbolSize);

  String encode() {
    final bytes = Uint8List(overhead + symbols.length);
    final view = ByteData.sublistView(bytes);
    view.setUint8(0, protocolVersion);
    view.setUint32(1, transferId);
    view.setUint32(5, totalLength);
    view.setUint32(9, firstSeq);
    bytes.setRange(headerSize, headerSize + symbols.length, symbols);
    final crcOffset = headerSize + symbols.length;
    view.setUint32(crcOffset, Crc32.compute(bytes, 0, crcOffset));
    return Base45.encode(bytes);
  }

  /// Returns null for anything that is not an intact frame of this protocol,
  /// e.g. an unrelated QR code in view or a misread.
  static Frame? decode(String text) {
    final bytes = Base45.decode(text);
    if (bytes == null || bytes.length < overhead + kSymbolSize) return null;
    final payloadLength = bytes.length - overhead;
    if (payloadLength % kSymbolSize != 0) return null;
    final view = ByteData.sublistView(bytes);
    if (view.getUint8(0) != protocolVersion) return null;
    final crcOffset = bytes.length - checksumSize;
    if (view.getUint32(crcOffset) != Crc32.compute(bytes, 0, crcOffset)) {
      return null;
    }
    final totalLength = view.getUint32(5);
    if (totalLength == 0) return null;
    return Frame(
      transferId: view.getUint32(1),
      totalLength: totalLength,
      firstSeq: view.getUint32(9),
      symbols: Uint8List.sublistView(bytes, headerSize, crcOffset),
    );
  }
}
