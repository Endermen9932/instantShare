import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/settings.dart';
import 'platform_info.dart';

/// Where a received file ended up.
class SavedFile {
  const SavedFile({required this.name, required this.location, this.uri});

  final String name;

  /// Human-readable place, e.g. a path or "Downloads/InstantShare".
  final String location;

  /// file:// or content:// URI to open the file with, if known.
  final Uri? uri;
}

const _channel = MethodChannel('instant_share/storage');

/// Received files land here automatically (no download dialog).
bool get savesAutomatically => true;

String get saveActionLabel => 'Speichern unter …';

Future<String> defaultSaveDirectory() async {
  final base =
      await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  return '${base.path}${Platform.pathSeparator}InstantShare';
}

Future<String> saveDirectoryFor(AppSettings settings) async =>
    settings.saveDirectory ?? await defaultSaveDirectory();

/// Stores a received file: Downloads/InstantShare on Android, the configured
/// folder on desktop.
Future<SavedFile> saveReceivedFile(
  AppSettings settings,
  String name,
  Uint8List bytes,
) async {
  if (PlatformInfo.isAndroid) {
    final uri = await _channel.invokeMethod<String>('saveToDownloads', {
      'name': name,
      'bytes': bytes,
    });
    if (uri != null) {
      return SavedFile(
        name: name,
        location: 'Download/InstantShare',
        uri: Uri.parse(uri),
      );
    }
    // Android 9 and older: let the user pick a place.
    return saveFileAs(name, bytes);
  }
  final dir = Directory(await saveDirectoryFor(settings));
  await dir.create(recursive: true);
  final file = _uniqueFile(dir, name);
  await file.writeAsBytes(bytes, flush: true);
  return SavedFile(name: name, location: file.path, uri: file.uri);
}

Future<SavedFile> saveFileAs(String name, Uint8List bytes) async {
  final uri = await FilePicker.saveFile(
    fileName: name,
    bytes: bytes,
    dialogTitle: 'Datei speichern',
  );
  if (uri == null) throw const FileSystemException('Speichern abgebrochen');
  // Some desktop implementations only return the chosen path.
  if (uri.scheme == 'file') {
    final file = File(uri.toFilePath());
    if (!await file.exists() || await file.length() != bytes.length) {
      await file.writeAsBytes(bytes, flush: true);
    }
  }
  return SavedFile(
    name: name,
    location: uri.scheme == 'file' ? uri.toFilePath() : name,
    uri: uri,
  );
}

File _uniqueFile(Directory dir, String name) {
  final sep = Platform.pathSeparator;
  var file = File('${dir.path}$sep$name');
  if (!file.existsSync()) return file;
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  final ext = dot > 0 ? name.substring(dot) : '';
  for (var i = 1; ; i++) {
    file = File('${dir.path}$sep$stem ($i)$ext');
    if (!file.existsSync()) return file;
  }
}

Future<bool> openSavedFile(SavedFile file) async {
  final uri = file.uri;
  if (uri == null) return false;
  if (PlatformInfo.isAndroid && uri.scheme == 'content') {
    try {
      await _channel.invokeMethod<void>('open', {'uri': uri.toString()});
      return true;
    } on PlatformException {
      return false;
    }
  }
  return launchUrl(uri);
}

bool get canOpenFolder => PlatformInfo.isDesktop;

Future<bool> openFolder(SavedFile file) async {
  final parent = File(file.location).parent;
  return launchUrl(Uri.directory(parent.path));
}

/// Web-only bulk download; files are already saved elsewhere.
Future<void> downloadFile(String name, Uint8List bytes) async {}
