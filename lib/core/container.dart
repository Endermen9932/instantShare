import 'dart:convert';
import 'dart:typed_data';

import 'compression.dart';
import 'crc32.dart';

enum PayloadKind { files, text }

class PayloadFile {
  const PayloadFile(this.name, this.bytes);

  final String name;
  final Uint8List bytes;
}

/// What a transfer carries: either files or a text message.
class TransferPayload {
  const TransferPayload.files(this.files) : kind = PayloadKind.files, text = null;

  TransferPayload.text(String this.text)
    : kind = PayloadKind.text,
      files = const [];

  final PayloadKind kind;
  final List<PayloadFile> files;
  final String? text;

  int get rawSize => kind == PayloadKind.text
      ? utf8.encode(text!).length
      : files.fold(0, (sum, f) => sum + f.bytes.length);
}

/// Metadata at the start of every container. Because it comes first and the
/// first symbols are sent unencoded, the receiver usually knows what is
/// coming within the first frame.
class ContainerHeader {
  const ContainerHeader({
    required this.kind,
    required this.files,
    required this.bodyLength,
    required this.compressed,
    required this.crc,
    required this.headerLength,
  });

  final PayloadKind kind;

  /// (name, size) pairs; empty for text.
  final List<(String, int)> files;

  /// Uncompressed length of the body.
  final int bodyLength;
  final bool compressed;
  final int crc;

  /// Bytes taken by the header itself within the container.
  final int headerLength;

  String get title {
    if (kind == PayloadKind.text) return 'Textnachricht';
    if (files.length == 1) return files.first.$1;
    return '${files.length} Dateien';
  }
}

class ContainerFormatException implements Exception {
  ContainerFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Container layout:
///   u8  container version
///   u32 length of the JSON metadata
///   ... JSON metadata (UTF-8)
///   ... body: the text or the files back to back, optionally raw deflate
abstract final class TransferContainer {
  static const int version = 1;

  static Uint8List build(TransferPayload payload, {bool compress = true}) {
    final Uint8List body;
    if (payload.kind == PayloadKind.text) {
      body = utf8.encode(payload.text!);
    } else {
      final builder = BytesBuilder(copy: false);
      for (final file in payload.files) {
        builder.add(file.bytes);
      }
      body = builder.takeBytes();
    }

    var stored = body;
    var compressed = false;
    if (compress && body.length > 64) {
      final deflated = rawDeflate(body);
      // Already compressed formats (jpg, zip, mp4, ...) do not shrink; storing
      // them as is saves the receiver the inflate step.
      if (deflated.length < body.length * 0.97) {
        stored = deflated;
        compressed = true;
      }
    }

    final meta = utf8.encode(
      jsonEncode({
        'kind': payload.kind.name,
        if (payload.kind == PayloadKind.files)
          'files': [
            for (final f in payload.files) {'name': f.name, 'size': f.bytes.length},
          ],
        'size': body.length,
        'crc': Crc32.compute(body),
        'deflate': compressed,
      }),
    );
    final out = Uint8List(5 + meta.length + stored.length);
    ByteData.sublistView(out)
      ..setUint8(0, version)
      ..setUint32(1, meta.length);
    out.setRange(5, 5 + meta.length, meta);
    out.setRange(5 + meta.length, out.length, stored);
    return out;
  }

  /// Parses the header from the first bytes of a container, or returns null
  /// while [prefix] is still too short.
  static ContainerHeader? tryParseHeader(Uint8List prefix) {
    if (prefix.length < 5) return null;
    final view = ByteData.sublistView(prefix);
    if (view.getUint8(0) != version) {
      throw ContainerFormatException('Unbekannte Container-Version');
    }
    final metaLength = view.getUint32(1);
    if (prefix.length < 5 + metaLength) return null;
    final Map<String, dynamic> json;
    try {
      json =
          jsonDecode(utf8.decode(Uint8List.sublistView(prefix, 5, 5 + metaLength)))
              as Map<String, dynamic>;
    } on FormatException {
      throw ContainerFormatException('Beschädigte Metadaten');
    }
    final kind = json['kind'] == 'text' ? PayloadKind.text : PayloadKind.files;
    final files = <(String, int)>[
      for (final f in (json['files'] as List<dynamic>? ?? const []))
        (_safeName((f as Map<String, dynamic>)['name'] as String), f['size'] as int),
    ];
    return ContainerHeader(
      kind: kind,
      files: files,
      bodyLength: json['size'] as int,
      compressed: json['deflate'] == true,
      crc: json['crc'] as int,
      headerLength: 5 + metaLength,
    );
  }

  static TransferPayload parse(Uint8List container) {
    final header = tryParseHeader(container);
    if (header == null) throw ContainerFormatException('Unvollständige Daten');
    var body = Uint8List.sublistView(container, header.headerLength);
    if (header.compressed) {
      try {
        body = rawInflate(body);
      } on Object {
        throw ContainerFormatException('Daten lassen sich nicht entpacken');
      }
    }
    if (body.length != header.bodyLength || Crc32.compute(body) != header.crc) {
      throw ContainerFormatException('Prüfsumme stimmt nicht');
    }
    if (header.kind == PayloadKind.text) {
      return TransferPayload.text(utf8.decode(body, allowMalformed: true));
    }
    final files = <PayloadFile>[];
    var offset = 0;
    for (final (name, size) in header.files) {
      if (offset + size > body.length) {
        throw ContainerFormatException('Dateigrößen passen nicht');
      }
      files.add(PayloadFile(name, Uint8List.sublistView(body, offset, offset + size)));
      offset += size;
    }
    return TransferPayload.files(files);
  }

  /// Strips path components and characters that are invalid on Windows, so a
  /// received name can never escape the target folder.
  static String _safeName(String name) {
    var base = name.split(RegExp(r'[\\/]')).last;
    base = base.replaceAll(RegExp(r'[<>:"|?*\x00-\x1F]'), '_').trim();
    if (base.isEmpty || base == '.' || base == '..') base = 'datei';
    return base;
  }
}
