import 'dart:io';
import 'dart:typed_data';

Uint8List rawDeflate(Uint8List data) =>
    Uint8List.fromList(ZLibCodec(raw: true, level: 6).encode(data));

Uint8List rawInflate(Uint8List data) =>
    Uint8List.fromList(ZLibCodec(raw: true).decode(data));
