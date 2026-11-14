// Built-in functions: waiting and time (wait, wait_until, now, clock...).
part of '../runtime.dart';

extension ScriptRuntimeBuiltinsTime on ScriptRuntime {
  void _registerTime() {
    _def('wait', (c) async {
      await this.sleep(_n(c, c.arg(0, 'ms'), 'wait'));
      return null;
    }, ['sleep', 'delay']);

    _def('now', (c) => DateTime.now().millisecondsSinceEpoch);
    _def('elapsed', (c) => _total.elapsedMilliseconds);
    String two(int n) => n.toString().padLeft(2, '0');
    _def('time', (c) {
      final d = DateTime.now();
      return '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
    });
    _def('date', (c) {
      final d = DateTime.now();
      return '${d.year}-${two(d.month)}-${two(d.day)}';
    });
    _def('clock', (c) {
      final d = DateTime.now();
      return <String, Object?>{
        'year': d.year,
        'month': d.month,
        'day': d.day,
        'weekday': d.weekday,
        'hour': d.hour,
        'minute': d.minute,
        'second': d.second,
      };
    });

    _def('wait_until', (c) async {
      final spec = _s(c, c.arg(0, 'time'), 'wait_until');
      final m = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$').firstMatch(spec.trim());
      if (m == null) c.fail('wait_until: время задаётся как "14:30" или "14:30:00"');
      final now = DateTime.now();
      var target = DateTime(now.year, now.month, now.day, int.parse(m.group(1)!),
          int.parse(m.group(2)!), int.parse(m.group(3) ?? '0'));
      if (!target.isAfter(now)) target = target.add(const Duration(days: 1));
      final mins = target.difference(now).inMinutes;
      log('Жду до $spec${target.day != now.day ? ' (завтра)' : ''} — '
          '${mins >= 60 ? '${mins ~/ 60} ч ${mins % 60} мин' : '$mins мин'}; '
          'часы сверяются раз в секунду');
      while (true) {
        final left = target.difference(DateTime.now()).inMilliseconds;
        if (left <= 0) break;
        await this.sleep(math.min(left, 1000), jitter: false);
      }
      log('Дождался $spec (сейчас ${two(DateTime.now().hour)}:${two(DateTime.now().minute)}:${two(DateTime.now().second)})');
      return null;
    });
  }
}
