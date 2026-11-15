// Statistics of a script counted from the run history: how often it ran,
// how long, how it ended, its most frequent error.

import 'app_controller.dart';

class ScriptStats {
  final String script;
  final int runs, ok, errors, stopped;
  final int totalMs, longestMs;
  final RunRecord last;

  /// The most frequent error text and how many times it happened.
  final String? topError;
  final int topErrorCount;

  const ScriptStats({
    required this.script,
    required this.runs,
    required this.ok,
    required this.errors,
    required this.stopped,
    required this.totalMs,
    required this.longestMs,
    required this.last,
    this.topError,
    this.topErrorCount = 0,
  });

  int get averageMs => runs == 0 ? 0 : totalMs ~/ runs;
}

/// Stats of every script in [history] (newest first, as the app keeps it),
/// the scripts run most recently first.
List<ScriptStats> scriptStats(List<RunRecord> history) {
  final by = <String, List<RunRecord>>{};
  for (final r in history) {
    by.putIfAbsent(r.script, () => []).add(r);
  }
  final out = [for (final e in by.entries) _stats(e.key, e.value)];
  out.sort((a, b) => b.last.started.compareTo(a.last.started));
  return out;
}

ScriptStats _stats(String script, List<RunRecord> runs) {
  var ok = 0, errors = 0, stopped = 0, total = 0, longest = 0;
  final errorCount = <String, int>{};
  var last = runs.first;
  for (final r in runs) {
    if (r.started.isAfter(last.started)) last = r;
    total += r.durationMs;
    if (r.durationMs > longest) longest = r.durationMs;
    switch (r.status) {
      case 'ok':
        ok++;
      case 'error':
        errors++;
        final e = r.error?.trim();
        if (e != null && e.isNotEmpty) errorCount[e] = (errorCount[e] ?? 0) + 1;
      default:
        stopped++; // stopped, killed, limit, closed
    }
  }
  String? top;
  var topN = 0;
  errorCount.forEach((e, n) {
    if (n > topN) {
      top = e;
      topN = n;
    }
  });
  return ScriptStats(
    script: script,
    runs: runs.length,
    ok: ok,
    errors: errors,
    stopped: stopped,
    totalMs: total,
    longestMs: longest,
    last: last,
    topError: top,
    topErrorCount: topN,
  );
}
