// A task of the schedule: run a script every day at a time, every N minutes
// or once at a date and time.


/// A script started automatically: every day at a time, every N minutes,
/// or once at a date and time.
class ScheduleTask {
  String script;
  String mode; // daily | interval | once
  String time; // HH:MM for daily and once
  String date; // YYYY-MM-DD for once
  int everyMin;
  bool enabled;
  DateTime? lastRun;
  ScheduleTask(
      {required this.script,
      this.mode = 'daily',
      this.time = '12:00',
      this.date = '',
      this.everyMin = 60,
      this.enabled = true,
      this.lastRun});

  factory ScheduleTask.fromJson(Map j) => ScheduleTask(
        script: '${j['script']}',
        mode: const ['interval', 'once'].contains(j['mode']) ? '${j['mode']}' : 'daily',
        time: '${j['time'] ?? '12:00'}',
        date: '${j['date'] ?? ''}',
        everyMin: (j['everyMin'] as num?)?.toInt() ?? 60,
        enabled: j['enabled'] != false,
        lastRun: DateTime.tryParse('${j['lastRun']}'),
      );

  Map<String, Object?> toJson() => {
        'script': script,
        'mode': mode,
        'time': time,
        'date': date,
        'everyMin': everyMin,
        'enabled': enabled,
        'lastRun': lastRun?.toIso8601String(),
      };

  /// Parses "H:MM" / "HH:MM"; null if invalid.
  static ({int h, int m})? parseTime(String t) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(t.trim());
    if (m == null) return null;
    final h = int.parse(m.group(1)!), mi = int.parse(m.group(2)!);
    if (h > 23 || mi > 59) return null;
    return (h: h, m: mi);
  }

  /// "14.11.2026", "14.11" (this year), "2026-11-14" → "2026-11-14";
  /// null if it is not a date.
  static String? parseDate(String d, {DateTime? now}) {
    final t = d.trim();
    int? y, mo, da;
    final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(t);
    final ru = RegExp(r'^(\d{1,2})\.(\d{1,2})(?:\.(\d{2}|\d{4}))?$').firstMatch(t);
    if (iso != null) {
      (y, mo, da) = (int.parse(iso[1]!), int.parse(iso[2]!), int.parse(iso[3]!));
    } else if (ru != null) {
      da = int.parse(ru[1]!);
      mo = int.parse(ru[2]!);
      y = ru[3] == null ? (now ?? DateTime.now()).year : int.parse(ru[3]!);
      if (y < 100) y += 2000;
    } else {
      return null;
    }
    final dt = DateTime(y, mo, da);
    if (dt.month != mo || dt.day != da) return null; // 31.02 and the like
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)}';
  }

  /// The moment of a one-time task; null if the date or time is wrong.
  DateTime? get onceAt {
    final d = parseDate(date), t = parseTime(time);
    if (d == null || t == null) return null;
    final p = d.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2], t.h, t.m);
  }

  /// "14.11.2026" for showing.
  String get dateLabel {
    final d = parseDate(date);
    if (d == null) return date;
    final p = d.split('-');
    return '${p[2]}.${p[1]}.${p[0]}';
  }

  String describe() => switch (mode) {
        'interval' => 'каждые $everyMin мин',
        'once' => 'один раз $dateLabel в $time${lastRun != null ? ' — выполнено' : ''}',
        _ => 'каждый день в $time',
      };

  /// Whether the task should start at [now]. [since] is when the schedule
  /// started being watched (app start), used for the first interval run.
  bool isDue(DateTime now, DateTime since) {
    if (!enabled) return false;
    if (mode == 'interval') {
      final base = lastRun ?? since;
      return now.difference(base).inSeconds >= everyMin.clamp(1, 100000) * 60;
    }
    if (mode == 'once') {
      final at = onceAt;
      if (at == null || lastRun != null || now.isBefore(at)) return false;
      return now.difference(at).inMinutes < 10; // missed by more — not run
    }
    final t = parseTime(time);
    if (t == null) return false;
    final target = DateTime(now.year, now.month, now.day, t.h, t.m);
    if (now.isBefore(target)) return false;
    // A missed start is still made within 10 minutes, but not later.
    if (now.difference(target).inMinutes >= 10) return false;
    return lastRun == null || lastRun!.isBefore(target);
  }
}
