// Where the user data lives: a "userdata" folder next to the program (a
// flash drive), the folder chosen in the settings, or %APPDATA%\SmartClicker.
// And moving / copying the data to another folder.

import 'dart:io';

/// Folder next to smart_clicker.exe: when it exists, the data is there.
const portableFolderName = 'userdata';

/// In the default folder: the path of the folder chosen in the settings.
/// (The settings themselves live in the data folder, so the way to it is
/// kept apart.)
const locationFileName = 'location.txt';

/// What belongs to SmartClicker in a data folder. Only these are copied,
/// moved or deleted: the user may pick a folder with other files in it.
const dataEntries = [
  'scripts', 'files', 'notes', 'logs', 'reports', 'ocr', //
  'settings.json', 'history.json', 'schedule.json', 'autorun.json',
  'notifications.json', 'data.json', 'answers.json',
];

/// How the data folder was found.
enum DataKind { standard, chosen, portable }

class DataLocation {
  final String dir;
  final DataKind kind;

  /// The chosen folder could not be reached (a drive that is not plugged
  /// in): the standard folder is used for now.
  final String? unreachable;
  const DataLocation(this.dir, this.kind, {this.unreachable});
}

String _join(String a, String b) => '$a${Platform.pathSeparator}$b';

/// %APPDATA%\SmartClicker (or ~/.config/SmartClicker).
String standardDataDir([Map<String, String>? env]) {
  final e = env ?? Platform.environment;
  final root = Platform.isWindows
      ? (e['APPDATA'] ?? e['USERPROFILE'] ?? '.')
      : _join(e['HOME'] ?? '.', '.config');
  return _join(root, 'SmartClicker');
}

String exeDir() {
  final exe = Platform.resolvedExecutable;
  return File(exe).parent.path;
}

String portableDir(String exeDir) => _join(exeDir, portableFolderName);

/// Order: next to the program, then the chosen folder, then the standard one.
DataLocation resolveDataLocation({required String standard, required String exeDir}) {
  final portable = portableDir(exeDir);
  if (Directory(portable).existsSync()) return DataLocation(portable, DataKind.portable);
  final chosen = readLocation(standard);
  if (chosen != null) {
    if (Directory(chosen).existsSync()) return DataLocation(chosen, DataKind.chosen);
    return DataLocation(standard, DataKind.standard, unreachable: chosen);
  }
  return DataLocation(standard, DataKind.standard);
}

String? readLocation(String standard) {
  try {
    final f = File(_join(standard, locationFileName));
    if (!f.existsSync()) return null;
    final p = f.readAsStringSync().trim();
    return p.isEmpty ? null : p;
  } catch (_) {
    return null;
  }
}

/// Remembers [dir] as the data folder; null (or the standard folder itself)
/// forgets the choice.
void writeLocation(String standard, String? dir) {
  final f = File(_join(standard, locationFileName));
  if (dir == null || samePath(dir, standard)) {
    if (f.existsSync()) f.deleteSync();
    return;
  }
  Directory(standard).createSync(recursive: true);
  f.writeAsStringSync(dir);
}

bool samePath(String a, String b) {
  String n(String p) {
    var s = p.replaceAll('/', r'\').trim();
    while (s.length > 3 && s.endsWith(r'\')) {
      s = s.substring(0, s.length - 1);
    }
    return Platform.isWindows ? s.toLowerCase() : s;
  }

  return n(a) == n(b);
}

/// [inner] is [outer] itself or somewhere inside it.
bool isInside(String inner, String outer) {
  final o = outer.replaceAll('/', r'\').toLowerCase();
  final i = inner.replaceAll('/', r'\').toLowerCase();
  return samePath(inner, outer) || i.startsWith(o.endsWith(r'\') ? o : '$o\\');
}

/// The folder holds SmartClicker data (settings or scripts).
bool looksLikeData(String dir) =>
    File(_join(dir, 'settings.json')).existsSync() || Directory(_join(dir, 'scripts')).existsSync();

/// Where the data goes when the user picks [chosen]: the folder itself if
/// it is empty or already SmartClicker's, otherwise a "SmartClicker"
/// folder inside it (so as not to mix with the user's own files).
String dataDirFor(String chosen) {
  final d = Directory(chosen);
  if (!d.existsSync() || looksLikeData(chosen) || d.listSync().isEmpty) return chosen;
  return _join(chosen, 'SmartClicker');
}

/// Number of files and their total size in the data entries of [dir].
({int files, int bytes}) measureData(String dir) {
  var files = 0, bytes = 0;
  for (final name in dataEntries) {
    final p = _join(dir, name);
    if (File(p).existsSync()) {
      files++;
      bytes += File(p).lengthSync();
    } else if (Directory(p).existsSync()) {
      for (final e in Directory(p).listSync(recursive: true)) {
        if (e is File) {
          files++;
          bytes += e.lengthSync();
        }
      }
    }
  }
  return (files: files, bytes: bytes);
}

/// Number of scripts in a data folder (for the "use what is there" question).
int scriptCount(String dir) {
  final d = Directory(_join(dir, 'scripts'));
  if (!d.existsSync()) return 0;
  return d.listSync(recursive: true).where((e) => e is File && e.path.endsWith('.cks')).length;
}

void _copyEntry(String from, String to) {
  if (File(from).existsSync()) {
    File(from).copySync(to);
    return;
  }
  final src = Directory(from);
  if (!src.existsSync()) return;
  Directory(to).createSync(recursive: true);
  for (final e in src.listSync(recursive: true)) {
    final rel = e.path.substring(src.path.length + 1);
    final target = _join(to, rel);
    if (e is Directory) {
      Directory(target).createSync(recursive: true);
    } else if (e is File) {
      File(target).parent.createSync(recursive: true);
      e.copySync(target);
    }
  }
}

void deleteData(String dir) {
  for (final name in dataEntries) {
    final p = _join(dir, name);
    if (File(p).existsSync()) File(p).deleteSync();
    if (Directory(p).existsSync()) Directory(p).deleteSync(recursive: true);
  }
}

/// What to do with the data when the folder changes.
enum DataMove {
  /// Copy, check that everything is there, then delete the old data.
  move,

  /// Copy; the old data stays where it was.
  copy,

  /// Start with an empty folder; the old data stays where it was.
  fresh,

  /// The new folder already has SmartClicker data: just use it.
  use,
}

/// Changes the data folder from [from] to [to]. Returns an error text, or
/// null when done. Runs in an isolate (copying may take a while).
String? changeDataFolder({
  required String from,
  required String to,
  required DataMove mode,
  required String standard,
  required String exeDir,
}) {
  if (samePath(from, to)) return 'Это и есть текущая папка с данными';
  if (isInside(to, from)) return 'Новая папка не может быть внутри текущей';
  try {
    Directory(to).createSync(recursive: true);
    // Can we write there at all (Program Files, a read-only drive)?
    final probe = File(_join(to, '.smartclicker_write_test'));
    probe.writeAsStringSync('ok');
    probe.deleteSync();
  } catch (_) {
    return 'В папку $to нельзя записывать. Выберите другую (например, в «Документах»)';
  }
  try {
    if (mode == DataMove.move || mode == DataMove.copy) {
      if (looksLikeData(to)) return 'В новой папке уже есть данные SmartClicker';
      for (final name in dataEntries) {
        _copyEntry(_join(from, name), _join(to, name));
      }
      final a = measureData(from), b = measureData(to);
      if (a.files != b.files || a.bytes != b.bytes) {
        return 'Скопировалось не всё (${b.files} из ${a.files} файлов). Старые данные не тронуты';
      }
    }
    final portable = portableDir(exeDir);
    if (samePath(from, portable) && !samePath(to, portable)) {
      // The "userdata" folder next to the program would win at the next
      // start: it goes away (moved) or is renamed (kept).
      if (mode == DataMove.move) {
        deleteData(from);
        final d = Directory(from);
        if (d.existsSync() && d.listSync().isEmpty) d.deleteSync();
      }
      final d = Directory(from);
      if (d.existsSync()) {
        var name = '$from (не используется)';
        for (var i = 2; Directory(name).existsSync(); i++) {
          name = '$from (не используется $i)';
        }
        d.renameSync(name);
      }
    } else if (mode == DataMove.move) {
      deleteData(from);
    }
    writeLocation(standard, samePath(to, portable) ? null : to);
    return null;
  } catch (e) {
    return 'Не получилось: $e';
  }
}
