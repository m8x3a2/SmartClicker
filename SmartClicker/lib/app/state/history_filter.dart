// Filters of the history of runs: by script, period, result, how it was
// started and text (error, script, log), and the order. Pure logic: the
// «История → Запуски» tab only shows the result.

import 'app_controller.dart';

enum HistoryPeriod { all, today, yesterday, week, days }

enum HistorySort { newest, oldest, longest }

const historyPeriodLabels = {
  HistoryPeriod.all: 'всё время',
  HistoryPeriod.today: 'сегодня',
  HistoryPeriod.yesterday: 'вчера',
  HistoryPeriod.week: '7 дней',
  HistoryPeriod.days: 'с … по …',
};

const historySortLabels = {
  HistorySort.newest: 'сначала новые',
  HistorySort.oldest: 'сначала старые',
  HistorySort.longest: 'самые долгие',
};

/// Results as the filter groups them.
const historyResultLabels = {
  'ok': 'успешно',
  'error': 'с ошибкой',
  'stopped': 'остановлен',
  'other': 'прерван, лимит, не отвечал',
};

String historyResultOf(String status) =>
    const {'ok', 'error', 'stopped'}.contains(status) ? status : 'other';

/// How a run was started, as the filter groups it.
const historyViaLabels = {
  'manual': 'вручную (кнопка, мини-панель, трей)',
  'key': 'клавишей',
  'schedule': 'по расписанию',
  'autorun': 'по программе',
  'file': 'по файлу',
  'external': 'извне (--run)',
  'restart': 'перезапуск после ошибки',
};

String historyViaOf(String via) => const {'mini', 'tray'}.contains(via) ? 'manual' : via;

/// The day of [d] (midnight).
DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

class HistoryFilter {
  String? script;
  HistoryPeriod period = HistoryPeriod.all;

  /// For [HistoryPeriod.days]: from and to (whole days, both included).
  DateTime? from, to;

  /// A key of [historyResultLabels] / [historyViaLabels]; null — any.
  String? result, via;
  String query = '';

  /// Search the logs of the runs too (they are files: slower).
  bool inLogs = false;
  HistorySort sort = HistorySort.newest;

  bool get active =>
      script != null ||
      period != HistoryPeriod.all ||
      result != null ||
      via != null ||
      query.trim().isNotEmpty;

  void reset() {
    script = null;
    period = HistoryPeriod.all;
    from = to = null;
    result = via = null;
    query = '';
    inLogs = false;
    sort = HistorySort.newest;
  }

  bool _inPeriod(DateTime t, DateTime now) {
    final today = dayOf(now);
    switch (period) {
      case HistoryPeriod.all:
        return true;
      case HistoryPeriod.today:
        return !t.isBefore(today);
      case HistoryPeriod.yesterday:
        final y = today.subtract(const Duration(days: 1));
        return !t.isBefore(y) && t.isBefore(today);
      case HistoryPeriod.week:
        return !t.isBefore(now.subtract(const Duration(days: 7)));
      case HistoryPeriod.days:
        final a = from == null ? null : dayOf(from!);
        final b = to == null ? null : dayOf(to!).add(const Duration(days: 1));
        return (a == null || !t.isBefore(a)) && (b == null || t.isBefore(b));
    }
  }

  /// The runs that pass, in the chosen order. [logText] reads the log of a
  /// run (only with [inLogs]).
  List<RunRecord> apply(List<RunRecord> runs, DateTime now, {String Function(String path)? logText}) {
    final q = query.trim().toLowerCase();
    final out = [
      for (final r in runs)
        if ((script == null || r.script == script) &&
            _inPeriod(r.started, now) &&
            (result == null || historyResultOf(r.status) == result) &&
            (via == null || historyViaOf(r.via) == via) &&
            (q.isEmpty || _matches(r, q, logText)))
          r
    ];
    switch (sort) {
      case HistorySort.newest:
        out.sort((a, b) => b.started.compareTo(a.started));
      case HistorySort.oldest:
        out.sort((a, b) => a.started.compareTo(b.started));
      case HistorySort.longest:
        out.sort((a, b) => b.durationMs.compareTo(a.durationMs));
    }
    return out;
  }

  bool _matches(RunRecord r, String q, String Function(String path)? logText) {
    if (r.script.toLowerCase().contains(q)) return true;
    if ((r.error ?? '').toLowerCase().contains(q)) return true;
    if ((r.source ?? '').toLowerCase().contains(q)) return true;
    if (inLogs && r.logFile != null && logText != null) {
      return logText(r.logFile!).toLowerCase().contains(q);
    }
    return false;
  }
}

/// The days that have runs (newest first) and how many runs each has.
List<(DateTime, int)> historyDays(List<RunRecord> runs) {
  final count = <DateTime, int>{};
  for (final r in runs) {
    final d = dayOf(r.started);
    count[d] = (count[d] ?? 0) + 1;
  }
  final days = count.keys.toList()..sort((a, b) => b.compareTo(a));
  return [for (final d in days) (d, count[d]!)];
}

/// The line of the error ("Строка 12: …" or "[Общее/бой] строка 10: …"), or 0.
int errorLineOf(RunRecord r) => errorPlaceOf(r).line;

/// Where the error is: the script (the one that ran, or another one it
/// connected with use / ran with run_script) and the line (0 — unknown).
({String script, int line}) errorPlaceOf(RunRecord r) {
  final e = r.error ?? '';
  final other = RegExp(r'^\[(.+?)\] строка (\d+):').firstMatch(e);
  if (other != null) return (script: other[1]!, line: int.parse(other[2]!));
  final m = RegExp(r'^Строка (\d+):').firstMatch(e);
  return (script: r.script, line: m == null ? 0 : int.parse(m[1]!));
}
