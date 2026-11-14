// A full backup of the data folder (one ZIP), restoring it, and resetting
// the program to "just installed". Only the program's own entries
// (dataEntries) are touched; logs, reports and OCR models are not backed up.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'data_location.dart';
import 'script_store.dart';
import 'zip.dart';

/// Description inside a backup archive.
const backupManifestName = 'smartclicker-backup.json';

/// What goes into a backup: everything but logs, reports and the OCR
/// models (big, and the models can be downloaded again).
final backupEntries = [
  for (final e in dataEntries)
    if (!const {'logs', 'reports', 'ocr'}.contains(e)) e,
];

/// What a reset deletes: everything of the program but the OCR models.
final resetEntries = [
  for (final e in dataEntries)
    if (e != 'ocr') e,
];

String _join(String a, String b) => '$a${Platform.pathSeparator}$b';

/// What a backup holds, counted for the confirmation windows.
class BackupInfo {
  final DateTime? created;
  final int scripts, pictures, notes, files;
  const BackupInfo(this.created, this.scripts, this.pictures, this.notes, this.files);

  String describe() => 'скриптов: $scripts, картинок: $pictures, заметок: $notes';
}

BackupInfo _count(Iterable<String> paths, DateTime? created) {
  var scripts = 0, pictures = 0, notes = 0, files = 0;
  for (final p in paths) {
    if (p == backupManifestName) continue;
    files++;
    final l = p.toLowerCase();
    if (l.startsWith('scripts/') && l.endsWith(ScriptStore.ext)) scripts++;
    if (l.startsWith('files/') && l.endsWith('.png')) pictures++;
    if (l.startsWith('notes/')) notes++;
  }
  return BackupInfo(created, scripts, pictures, notes, files);
}

/// What is in the data folder [dir] now (for the reset window).
BackupInfo countData(String dir) {
  final paths = <String>[];
  for (final e in backupEntries) {
    final d = Directory(_join(dir, e));
    if (d.existsSync()) {
      for (final f in d.listSync(recursive: true).whereType<File>()) {
        paths.add('$e/${f.path.substring(d.path.length + 1).replaceAll(r'\', '/')}');
      }
    }
  }
  return _count(paths, null);
}

/// One ZIP with [backupEntries] of the data folder [dir]. [scripts] (name →
/// text) replaces the scripts on disk: unsaved edits are included.
Uint8List makeBackup(String dir, {Map<String, String>? scripts, DateTime? now}) {
  final files = <String, List<int>>{
    backupManifestName: utf8.encode(jsonEncode({
      'format': 1,
      'created': (now ?? DateTime.now()).toIso8601String(),
    })),
  };
  for (final e in backupEntries) {
    if (e == 'scripts' && scripts != null) {
      scripts.forEach((n, t) => files['scripts/$n${ScriptStore.ext}'] = utf8.encode(t));
      continue;
    }
    final p = _join(dir, e);
    if (File(p).existsSync()) {
      files[e] = File(p).readAsBytesSync();
    } else if (Directory(p).existsSync()) {
      for (final f in Directory(p).listSync(recursive: true).whereType<File>()) {
        files['$e/${f.path.substring(p.length + 1).replaceAll(r'\', '/')}'] = f.readAsBytesSync();
      }
    }
  }
  return zipEncode(files);
}

/// Reads a backup; throws FormatException if it is not one.
({Map<String, Uint8List> files, BackupInfo info}) readBackup(Uint8List bytes) {
  final files = zipDecode(bytes);
  final manifest = files[backupManifestName];
  if (manifest == null) {
    throw const FormatException('Это не резервная копия SmartClicker (нет описания внутри)');
  }
  DateTime? created;
  try {
    created = DateTime.tryParse('${(jsonDecode(utf8.decode(manifest)) as Map)['created']}');
  } catch (_) {}
  return (files: files, info: _count(files.keys, created));
}

/// Whether [path] of an archive may be written into the data folder: one
/// of [backupEntries], no way out of the folder.
bool _allowed(String path) {
  final p = path.replaceAll(r'\', '/');
  if (p.startsWith('/') || p.contains(':') || p.split('/').contains('..')) return false;
  final top = p.split('/').first;
  return backupEntries.contains(top) && (p.contains('/') || !const {'scripts', 'files', 'notes'}.contains(top));
}

/// Deletes the program's entries ([entries], by default [resetEntries]) in
/// the data folder [dir]. Other files there stay.
void resetData(String dir, [List<String>? entries]) {
  for (final e in entries ?? resetEntries) {
    final p = _join(dir, e);
    if (File(p).existsSync()) File(p).deleteSync();
    if (Directory(p).existsSync()) Directory(p).deleteSync(recursive: true);
  }
}

/// Replaces the data of [dir] with the backup [files]: what the backup
/// holds is deleted first, then written from the archive.
void restoreBackup(String dir, Map<String, Uint8List> files) {
  resetData(dir, backupEntries);
  files.forEach((path, data) {
    if (path == backupManifestName || !_allowed(path)) return;
    final f = File(_join(dir, path.replaceAll('/', Platform.pathSeparator)));
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(data);
  });
}
