// Rules "start a script when a file changes" (a neural network wrote a
// task) and their checking: pure logic, no timers and no disk — the caller
// passes the state of the files.

/// How a rule starts its script.
enum FileRunMode {
  /// Ask first (a strip with "Запустить" / "Отменить"; no answer — not run).
  ask,

  /// Run in the test mode: actions only go to the log.
  test,

  /// Just run.
  run,
}

/// A script tied to a file.
class FileRule {
  String script;

  /// Full path of the file, or a name in the files folder ("задание.json").
  String path;

  /// Empty — any change; otherwise a JSON key ("ready", "a.b"): the script
  /// starts only when its value is "yes" (true, not 0, not empty).
  String key;
  FileRunMode mode;

  /// Not more often than once in this many seconds.
  int minGapSec;
  bool enabled;
  DateTime? lastRun;

  FileRule({
    required this.script,
    required this.path,
    this.key = '',
    this.mode = FileRunMode.ask,
    this.minGapSec = 30,
    this.enabled = true,
    this.lastRun,
  });

  factory FileRule.fromJson(Map j) => FileRule(
        script: '${j['script']}',
        path: '${j['path'] ?? ''}',
        key: '${j['key'] ?? ''}',
        mode: FileRunMode.values.firstWhere((m) => m.name == j['mode'],
            orElse: () => FileRunMode.ask),
        minGapSec: (j['minGapSec'] as num?)?.toInt().clamp(0, 86400) ?? 30,
        enabled: j['enabled'] != false,
        lastRun: DateTime.tryParse('${j['lastRun']}'),
      );

  Map<String, Object?> toJson() => {
        'script': script,
        'path': path,
        'key': key,
        'mode': mode.name,
        'minGapSec': minGapSec,
        'enabled': enabled,
        'lastRun': lastRun?.toIso8601String(),
      };

  String describe() {
    final when = key.isEmpty
        ? 'когда меняется «$path»'
        : 'когда в «$path» значение «$key» становится «да»';
    final how = switch (mode) {
      FileRunMode.ask => '; сначала спросить',
      FileRunMode.test => '; в тестовом режиме (без кликов)',
      FileRunMode.run => '',
    };
    return '$when$how; не чаще раза в $minGapSec с';
  }
}

/// A change of a file is noticed only when it stays the same this long:
/// another program may still be writing it.
const fileSettle = Duration(seconds: 1);

class _FileSeen {
  String stamp; // what the file was when last handled ('' — no file)
  String? pending; // a new stamp waiting to settle
  DateTime? pendingSince;
  _FileSeen(this.stamp);
}

/// What happened to a rule in one check.
enum FileEvent { fire, tooSoon, notReady }

/// Watches the files of the rules. The caller passes, for a path, its
/// "stamp" (time and size, '' — no file) and, for a JSON key, whether its
/// value is "yes"; [check] is called once a second.
class FileWatch {
  final Map<FileRule, _FileSeen> _seen = Map.identity();

  List<(FileRule, FileEvent)> check(
    List<FileRule> rules,
    String Function(String path) stampOf,
    bool Function(String path, String key) keyIsYes,
    DateTime now,
  ) {
    final out = <(FileRule, FileEvent)>[];
    for (final r in rules) {
      if (!r.enabled || r.path.trim().isEmpty) {
        _seen.remove(r);
        continue;
      }
      final stamp = stampOf(r.path);
      final seen = _seen[r];
      if (seen == null) {
        // What is there when watching begins is not a change.
        _seen[r] = _FileSeen(stamp);
        continue;
      }
      if (stamp == seen.stamp) {
        seen.pending = null;
        continue;
      }
      if (seen.pending != stamp) {
        seen.pending = stamp;
        seen.pendingSince = now;
        continue;
      }
      if (now.difference(seen.pendingSince!) < fileSettle) continue;
      // Settled: the change is handled now, whatever comes of it.
      seen.stamp = stamp;
      seen.pending = null;
      if (stamp.isEmpty) continue; // the file was deleted: not a task
      if (r.key.isNotEmpty && !keyIsYes(r.path, r.key)) {
        out.add((r, FileEvent.notReady));
        continue;
      }
      final last = r.lastRun;
      if (last != null && now.difference(last).inSeconds < r.minGapSec) {
        out.add((r, FileEvent.tooSoon));
        continue;
      }
      out.add((r, FileEvent.fire));
    }
    _seen.removeWhere((r, _) => !rules.contains(r));
    return out;
  }
}
