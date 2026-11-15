// Profiler: where the time of a run went — per line of the main script (a
// `run_script` line holds the time of the whole script it runs) and per
// built-in function (calls, total time). Sent with the end of the run.
part of 'runtime.dart';

extension _RuntimeProfile on ScriptRuntime {
  /// A new line of the main script starts: the time since the previous one
  /// goes to that previous line.
  void _profileLine(int line) {
    if (_nested != 0) return;
    if (_profLine > 0) _lineUs[_profLine] = (_lineUs[_profLine] ?? 0) + _profSw.elapsedMicroseconds;
    _lineHits[line] = (_lineHits[line] ?? 0) + 1;
    _profLine = line;
    _profSw.reset();
  }

  /// A built-in function with its time counted.
  BuiltinFn _timed(String name, BuiltinFn fn) => (c) {
        final t0 = _profClock.elapsedMicroseconds;
        final r = fn(c);
        if (r is Future<Object?>) return r.whenComplete(() => _addCall(name, t0));
        _addCall(name, t0);
        return r;
      };

  void _addCall(String name, int t0) {
    final s = _callStats.putIfAbsent(name, () => [0, 0]);
    s[0]++;
    s[1] += _profClock.elapsedMicroseconds - t0;
  }

  /// The profile for the end event: the 60 slowest lines [line, µs, times]
  /// and the 40 slowest functions [name, calls, µs].
  Map<String, Object?> _profile() {
    if (_profLine > 0) {
      _lineUs[_profLine] = (_lineUs[_profLine] ?? 0) + _profSw.elapsedMicroseconds;
      _profLine = 0;
    }
    final lines = _lineUs.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final calls = _callStats.entries.toList()..sort((a, b) => b.value[1].compareTo(a.value[1]));
    return {
      'lines': [
        for (final e in lines.take(60)) [e.key, e.value, _lineHits[e.key] ?? 0]
      ],
      'calls': [
        for (final e in calls.take(40)) [e.key, e.value[0], e.value[1]]
      ],
    };
  }
}
