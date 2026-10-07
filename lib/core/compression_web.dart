import 'dart:typed_data';

import 'package:archive/archive.dart';

Uint8List rawDeflate(Uint8List data) => Deflate(data).getBytes();

Uint8List rawInflate(Uint8List data) => Inflate(data).getBytes();
