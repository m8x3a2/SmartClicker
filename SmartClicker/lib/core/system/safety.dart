// Safety: safe mode at start (rescue files safe.txt / reset.txt, a loop of
// crashing starts) and the guard against self-destruction — rules that keep
// a script from breaking the computer or the program beyond a human's reach.

import 'dart:convert';
import 'dart:io';

/// Start parameter: open in safe mode.
const safeArg = '--safe';

/// Windows must have been running this long before a script may switch it
/// off: otherwise a script started by the schedule or autorun could restart
/// the computer in a loop.
const powerMinUptime = Duration(minutes: 5);

/// A script may switch the computer off at most once in this time.
const powerMinGap = Duration(minutes: 30);

/// This many starts in a row that ended without a normal exit within
/// [crashLoopWindow] — the next start is in safe mode.
const crashLoopStarts = 3;
const crashLoopWindow = Duration(minutes: 3);

/// Automation waits this long after a start together with Windows (default
/// of the setting).
const defaultAutostartDelaySec = 300;

/// Actions of `system_power` that switch the computer off (lock does not).
const powerOffActions = {'sleep', 'hibernate', 'shutdown', 'restart', 'logoff'};

/// Processes a script may not end: the program itself and the parts of
/// Windows without which the desktop, input or the session break.
const protectedProcesses = {
  'smart_clicker', 'explorer', 'winlogon', 'csrss', 'lsass', 'services',
  'smss', 'wininit', 'dwm', 'svchost', 'system', 'registry', 'fontdrvhost',
  'sihost', 'ctfmon', 'taskhostw', 'logonui',
};

/// Process name as `kill_process` takes it: "Game.exe", "C:\\x\\game.exe" and
/// "game|Заголовок" all become "game".
String processBaseName(String query) {
  var n = query.split('|').first.trim().toLowerCase();
  final cut = n.lastIndexOf(RegExp(r'[\\/]'));
  if (cut >= 0) n = n.substring(cut + 1);
  if (n.endsWith('.exe')) n = n.substring(0, n.length - 4);
  return n;
}

/// The protected process [query] names, or null.
String? protectedProcess(String query) {
  final n = processBaseName(query);
  return protectedProcesses.contains(n) ? n : null;
}

final _powerCommand = RegExp(
    r'\bshutdown(\.exe)?\b|restart-computer|stop-computer|\blogoff(\.exe)?\b|'
    r'setsuspendstate|\btsdiscon\b',
    caseSensitive: false);
final _abortShutdown = RegExp(r'\bshutdown(\.exe)?\s+[/-]a\b', caseSensitive: false);

/// A command line that switches the computer off ("shutdown /r /t 0",
/// "powershell Restart-Computer"). Cancelling a shutdown (`shutdown /a`)
/// is not one.
bool isPowerCommand(String cmd) =>
    _powerCommand.hasMatch(cmd) && !_abortShutdown.hasMatch(cmd);

/// Why switching the computer off is not allowed now, or null. [uptimeMs] —
/// how long Windows runs, [recent] — when scripts switched it off before.
String? powerBlockReason({
  required int uptimeMs,
  required List<DateTime> recent,
  required DateTime now,
}) {
  if (uptimeMs < powerMinUptime.inMilliseconds) {
    final min = (uptimeMs / 60000).floor();
    return 'Windows включена только $min мин назад, а в первые '
        '${powerMinUptime.inMinutes} минут скрипты не выключают и не перезагружают компьютер '
        '(иначе скрипт из расписания или автозапуска может перезагружать его по кругу)';
  }
  DateTime? last;
  for (final t in recent) {
    if (last == null || t.isAfter(last)) last = t;
  }
  if (last != null && now.difference(last) < powerMinGap) {
    final ago = now.difference(last).inMinutes;
    return 'скрипт уже выключал или перезагружал компьютер $ago мин назад, а чаще раза в '
        '${powerMinGap.inMinutes} минут это не делается (защита от петли перезагрузок)';
  }
  return null;
}

/// Why a script may not write the file [path], or null. The program folder
/// and its data folder are protected, except the files folder of scripts.
String? protectedWrite(String path,
    {required String dataDir, required String filesDir, required String exeDir}) {
  final p = _norm(path);
  bool inside(String dir) {
    final d = _norm(dir);
    return d.isNotEmpty && (p == d || p.startsWith('$d\\'));
  }

  if (inside(filesDir)) return null;
  if (inside(dataDir)) {
    return 'это папка данных SmartClicker (скрипты, настройки) — скрипт может писать только '
        'в папку files или в другие папки';
  }
  if (inside(exeDir)) return 'это папка самой программы SmartClicker';
  return null;
}

String _norm(String path) {
  if (path.trim().isEmpty) return '';
  var p = File(path).absolute.uri.normalizePath().toFilePath(windows: true);
  p = p.replaceAll('/', '\\').toLowerCase();
  while (p.endsWith('\\')) {
    p = p.substring(0, p.length - 1);
  }
  return p;
}

/// One start of the program and whether it ended with a normal exit.
class LaunchRecord {
  final DateTime at;
  bool clean;
  LaunchRecord(this.at, {this.clean = false});
}

/// The last [crashLoopStarts] starts before now all ended without a normal
/// exit (crashed, killed) within [crashLoopWindow].
bool isCrashLoop(List<LaunchRecord> before, DateTime now) {
  final recent = [
    for (final l in before)
      if (now.difference(l.at) <= crashLoopWindow && !now.isBefore(l.at)) l
  ];
  if (recent.length < crashLoopStarts) return false;
  return recent.reversed.take(crashLoopStarts).every((l) => !l.clean);
}

/// Journal of the guard (safety.json in the data folder): starts of the
/// program and when scripts switched the computer off. Not moved with the
/// data: it only matters on this computer and only for a short time.
class SafetyJournal {
  final String path;
  final List<LaunchRecord> launches = [];
  final List<DateTime> power = [];
  SafetyJournal(this.path);

  factory SafetyJournal.load(String path) {
    final j = SafetyJournal(path);
    try {
      final f = File(path);
      if (!f.existsSync()) return j;
      final d = jsonDecode(f.readAsStringSync());
      if (d is! Map) return j;
      for (final l in (d['launches'] as List? ?? const [])) {
        if (l is! Map) continue;
        final at = DateTime.tryParse('${l['at']}');
        if (at != null) j.launches.add(LaunchRecord(at, clean: l['clean'] == true));
      }
      for (final p in (d['power'] as List? ?? const [])) {
        final at = DateTime.tryParse('$p');
        if (at != null) j.power.add(at);
      }
    } catch (_) {
      // A broken journal must not stop the program: start with an empty one.
    }
    return j;
  }

  void save() {
    // Only the recent past matters.
    while (launches.length > 10) {
      launches.removeAt(0);
    }
    while (power.length > 10) {
      power.removeAt(0);
    }
    try {
      File(path).writeAsStringSync(jsonEncode({
        'launches': [
          for (final l in launches) {'at': l.at.toIso8601String(), 'clean': l.clean}
        ],
        'power': [for (final p in power) p.toIso8601String()],
      }));
    } catch (_) {
      // Read-only folder: the guard simply remembers less.
    }
  }
}

/// What the rescue files asked for.
class RescueRequest {
  bool safe = false;
  bool reset = false;

  /// Which files were found (full paths), for the message.
  final List<String> found = [];
  bool get any => safe || reset;
}

/// Words in reset.txt that ask for a reset (an empty or other file is
/// ignored and left in place).
const resetWords = {'reset', 'true', 'да', 'yes', '1', 'сброс'};

/// Looks for safe.txt and reset.txt in [dirs] (next to the program and in
/// the data folder); the files that were acted on are deleted.
RescueRequest takeRescueFiles(List<String> dirs) {
  final r = RescueRequest();
  final sep = Platform.pathSeparator;
  for (final dir in dirs.toSet()) {
    final safe = File('$dir${sep}safe.txt');
    if (safe.existsSync()) {
      r.safe = true;
      r.found.add(safe.path);
      _delete(safe);
    }
    final reset = File('$dir${sep}reset.txt');
    if (reset.existsSync()) {
      var text = '';
      try {
        text = reset.readAsStringSync().trim().toLowerCase();
      } catch (_) {}
      if (resetWords.contains(text)) {
        r.reset = true;
        r.found.add(reset.path);
        _delete(reset);
      }
    }
  }
  return r;
}

void _delete(File f) {
  try {
    f.deleteSync();
  } catch (_) {}
}

/// Moves [files] (settings, schedule, autorun) into [backupDir] — the program
/// then starts with defaults, and nothing is lost. Returns the moved names.
List<String> moveAside(List<String> files, String backupDir) {
  final moved = <String>[];
  final sep = Platform.pathSeparator;
  for (final path in files) {
    final f = File(path);
    if (!f.existsSync()) continue;
    try {
      Directory(backupDir).createSync(recursive: true);
      final name = path.substring(path.lastIndexOf(sep) + 1);
      f.copySync('$backupDir$sep$name');
      f.deleteSync();
      moved.add(name);
    } catch (_) {}
  }
  return moved;
}
