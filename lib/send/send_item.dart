import 'dart:convert';
import 'dart:typed_data';

import '../core/container.dart';
import '../util/background.dart';

/// Something the user queued for sending.
sealed class SendItem {
  const SendItem();

  String get name;
  int get size;
}

class FileItem extends SendItem {
  const FileItem({required this.name, required this.size, required this.read});

  @override
  final String name;

  @override
  final int size;

  final Future<Uint8List> Function() read;
}

class TextItem extends SendItem {
  const TextItem(this.text);

  final String text;

  @override
  String get name => 'Textnachricht';

  @override
  int get size => utf8.encode(text).length;
}

/// Turns the queue into a transfer container. A lone text becomes a text
/// message; mixed with files it travels as a .txt file.
Future<Uint8List> buildContainer(
  List<SendItem> items, {
  required bool compress,
}) async {
  final TransferPayload payload;
  if (items.length == 1 && items.single is TextItem) {
    payload = TransferPayload.text((items.single as TextItem).text);
  } else {
    final files = <PayloadFile>[];
    var textIndex = 0;
    for (final item in items) {
      switch (item) {
        case FileItem():
          files.add(PayloadFile(item.name, await item.read()));
        case TextItem():
          textIndex++;
          files.add(
            PayloadFile(
              textIndex == 1 ? 'Text.txt' : 'Text $textIndex.txt',
              Uint8List.fromList(utf8.encode(item.text)),
            ),
          );
      }
    }
    payload = TransferPayload.files(files);
  }
  return runInBackground(
    () => TransferContainer.build(payload, compress: compress),
  );
}
