// Folders and files of the user data (where the data folder is — see
// data_location.dart) and JSON read/write helpers.

import 'dart:convert';
import 'dart:io';

import 'data_location.dart';

/// Locations of user data on disk.
class AppPaths {
  final String base;

  /// How [base] was found (standard / chosen in the settings / next to the
  /// program) and whether the chosen folder could not be reached.
  final DataLocation location;
  AppPaths(this.base, {DataLocation? location})
      : location = location ?? DataLocation(base, DataKind.standard);

  factory AppPaths.detect() {
    final loc = resolveDataLocation(standard: standardDataDir(), exeDir: exeDir());
    return AppPaths(loc.dir, location: loc);
  }

  String _p(String name) => '$base${Platform.pathSeparator}$name';
  String get scripts => _p('scripts');
  String get logs => _p('logs');
  String get files => _p('files');
  String get notes => _p('notes');
  /// Folder of the accurate text recognition: the one shipped next to the
  /// executable (data/ocr), otherwise the user's own (downloaded / imported).
  String get ocr {
    final sep = Platform.pathSeparator;
    final exe = Platform.resolvedExecutable;
    final cut = exe.lastIndexOf(sep);
    if (cut > 0) {
      final shipped = '${exe.substring(0, cut)}${sep}data${sep}ocr';
      if (File('$shipped${sep}onnxruntime.dll').existsSync()) return shipped;
    }
    return _p('ocr');
  }
  String get settingsFile => _p('settings.json');
  String get historyFile => _p('history.json');
  String get scheduleFile => _p('schedule.json');
  String get autorunFile => _p('autorun.json');
  /// Scripts started when a file changes (Автозапуск → «По файлу»).
  String get fileRulesFile => _p('file_rules.json');
  /// Clipboard history: index.json and pictures (the «Буфер» page).
  String get clipboard => _p('clipboard');
  /// Deleted scripts, folders and pictures (kept for 30 days).
  String get trash => _p('trash');
  String get notificationsFile => _p('notifications.json');
  String get dataFile => _p('data.json');
  /// Journal of the guard against self-destruction (starts of the program,
  /// when scripts switched the computer off). Not in dataEntries on purpose:
  /// it only matters on this computer, for minutes.
  String get safetyFile => _p('safety.json');
  /// Requests of other programs to this copy (--run / --stop); read and
  /// deleted at once, so not in dataEntries.
  String get requests => _p('requests');
  /// Last answers to the questions of scripts (ask).
  String get answersFile => _p('answers.json');
  String get reports => _p('reports');
  /// Errors of the program itself (not of scripts).
  String get appErrorsFile => '$logs${Platform.pathSeparator}app_errors.log';

  void ensure() {
    for (final d in [base, scripts, logs, files, notes, reports]) { // ocr: made on demand
      Directory(d).createSync(recursive: true);
    }
  }
}

Object? readJson(String path) {
  try {
    final f = File(path);
    if (f.existsSync()) return jsonDecode(f.readAsStringSync());
  } catch (_) {}
  return null;
}

void writeJson(String path, Object? value) {
  try {
    File(path).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(value));
  } catch (_) {}
}
