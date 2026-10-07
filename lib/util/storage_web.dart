import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../app/settings.dart';

class SavedFile {
  const SavedFile({required this.name, required this.location, this.uri});

  final String name;
  final String location;
  final Uri? uri;
}

/// Browsers need a user gesture per download, so nothing is saved
/// automatically.
bool get savesAutomatically => false;

String get saveActionLabel => 'Herunterladen';

Future<String> defaultSaveDirectory() async => 'Downloads';

Future<String> saveDirectoryFor(AppSettings settings) async => 'Downloads';

Future<SavedFile> saveReceivedFile(
  AppSettings settings,
  String name,
  Uint8List bytes,
) async {
  await downloadFile(name, bytes);
  return SavedFile(name: name, location: 'Downloads');
}

Future<SavedFile> saveFileAs(String name, Uint8List bytes) async {
  await downloadFile(name, bytes);
  return SavedFile(name: name, location: 'Downloads');
}

Future<void> downloadFile(String name, Uint8List bytes) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/octet-stream'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = name
    ..style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  // Give the browser a moment to start the download before revoking.
  Future<void>.delayed(
    const Duration(seconds: 30),
    () => web.URL.revokeObjectURL(url),
  );
}

Future<bool> openSavedFile(SavedFile file) async => false;

bool get canOpenFolder => false;

Future<bool> openFolder(SavedFile file) async => false;
