// «Сторож»: a game (any program) crashed or hung while its script works —
// stop the script, close the program, start it again, wait for its window
// and the loading, start the script again. Pure logic: the caller passes
// what it sees and does the actions.

/// A guarded program and its script.
class GuardRule {
  /// The process of the program: "game.exe".
  String process;

  /// How to start it again: a path to the exe, a shortcut (.lnk) or a link
  /// ("steam://rungameid/…"). Empty — the path is not known: only stop the
  /// script and tell.
  String launch;

  /// The script that works with the program: the guard watches while it runs.
  String script;

  /// The window "Не отвечает" longer than this — a hang (0 — not checked).
  int hangSec;

  /// After the window appears: time for the program to load, s.
  int loadSec;

  /// Not more restarts in an hour; then the guard gives up and tells.
  int maxPerHour;
  bool enabled;

  /// Restarts of the last hour (for [maxPerHour]) and the last one.
  final List<DateTime> restarts;

  GuardRule({
    required this.process,
    required this.script,
    this.launch = '',
    this.hangSec = 30,
    this.loadSec = 30,
    this.maxPerHour = 3,
    this.enabled = true,
    List<DateTime>? restarts,
  }) : restarts = restarts ?? [];

  factory GuardRule.fromJson(Map j) => GuardRule(
        process: '${j['process'] ?? ''}',
        script: '${j['script'] ?? ''}',
        launch: '${j['launch'] ?? ''}',
        hangSec: (j['hangSec'] as num?)?.toInt().clamp(0, 3600) ?? 30,
        loadSec: (j['loadSec'] as num?)?.toInt().clamp(0, 3600) ?? 30,
        maxPerHour: (j['maxPerHour'] as num?)?.toInt().clamp(1, 60) ?? 3,
        enabled: j['enabled'] != false,
        restarts: [
          for (final t in (j['restarts'] as List?) ?? const []) ?DateTime.tryParse('$t'),
        ],
      );

  Map<String, Object?> toJson() => {
        'process': process,
        'script': script,
        'launch': launch,
        'hangSec': hangSec,
        'loadSec': loadSec,
        'maxPerHour': maxPerHour,
        'enabled': enabled,
        'restarts': [for (final t in restarts) t.toIso8601String()],
      };

  /// "game.exe" from "game" or "C:\Games\game.exe".
  static String processName(String s) {
    var n = s.trim().replaceAll(r'\', '/').split('/').last.toLowerCase();
    if (n.isEmpty) return n;
    if (!n.endsWith('.exe')) n = '$n.exe';
    return n;
  }

  String describe() =>
      'пока работает «$script»: если $process закроется${hangSec > 0 ? ' или не отвечает дольше $hangSec с' : ''} — '
      '${launch.trim().isEmpty ? 'остановить скрипт и сообщить' : 'запустить снова, через $loadSec с после появления окна — скрипт'}; '
      'не больше $maxPerHour раз в час';
}

/// What the program looks like now.
typedef GuardSeen = ({bool running, bool hung});

/// What the caller has to do.
enum GuardDo {
  /// Stop the script (if it runs) and close the program (if it is there).
  stopAndClose,

  /// Start the program.
  launch,

  /// Start the script again.
  runScript,

  /// Too many restarts, no way to start, or the program did not start:
  /// tell and stop watching until the script is started again.
  giveUp,
}

/// One step of the guard: what to do and why (for the log and the user).
typedef GuardStep = ({GuardRule rule, GuardDo act, String why});

/// [off] — gave up: silent until the script is started again (or stopped).
enum _Phase { watch, closing, starting, loading, off }

class _State {
  _Phase phase = _Phase.watch;
  DateTime? since; // the phase began / the trouble was first seen
  DateTime? missing; // the process is not seen since
  DateTime? hung; // the window does not respond since
}

/// The process missing this long is a crash (a restart of the program by
/// itself — an updater — takes a moment).
const guardMissing = Duration(seconds: 3);

/// Time between closing the program and starting it again.
const guardClosePause = Duration(seconds: 2);

/// The program must show itself this soon after it was started.
const guardStartTimeout = Duration(minutes: 2);

class GuardWatch {
  final Map<GuardRule, _State> _st = Map.identity();

  /// Forgets the state of a rule (the script was stopped by the user).
  void reset(GuardRule r) => _st.remove(r);

  /// The rule is restarting the program now (the guard stops the script
  /// itself: that stop does not end the watching).
  bool busy(GuardRule r) {
    final p = _st[r]?.phase ?? _Phase.watch;
    return p != _Phase.watch && p != _Phase.off;
  }

  /// Called once a second. [armed] — whether the rule watches now (its
  /// script was started and not stopped by the user); [seen] — the state
  /// of its program; [scriptBusy] — some script runs now (a new one is not
  /// started over it).
  List<GuardStep> check(
    List<GuardRule> rules,
    bool Function(GuardRule) armed,
    GuardSeen Function(GuardRule) seen,
    bool scriptBusy,
    DateTime now,
  ) {
    final out = <GuardStep>[];
    for (final r in rules) {
      if (!r.enabled || r.process.trim().isEmpty) {
        _st.remove(r);
        continue;
      }
      final st = _st.putIfAbsent(r, _State.new);
      if (st.phase == _Phase.off) {
        if (!armed(r)) st.phase = _Phase.watch;
        continue;
      }
      if (st.phase == _Phase.watch && !armed(r)) {
        st.missing = null;
        st.hung = null;
        continue;
      }
      final s = seen(r);
      switch (st.phase) {
        case _Phase.watch:
          st.missing = s.running ? null : (st.missing ?? now);
          st.hung = s.running && s.hung ? (st.hung ?? now) : null;
          String? why;
          if (st.missing != null && now.difference(st.missing!) >= guardMissing) {
            why = '${r.process} закрылась';
          } else if (r.hangSec > 0 && st.hung != null && now.difference(st.hung!).inSeconds >= r.hangSec) {
            why = '${r.process} не отвечает ${now.difference(st.hung!).inSeconds} с';
          }
          if (why == null) break;
          r.restarts.removeWhere((t) => now.difference(t) >= const Duration(hours: 1));
          if (r.launch.trim().isEmpty) {
            out.add((rule: r, act: GuardDo.stopAndClose, why: why));
            out.add((rule: r, act: GuardDo.giveUp, why: '$why; как её запустить, не указано'));
            st.phase = _Phase.off;
          } else if (r.restarts.length >= r.maxPerHour) {
            out.add((rule: r, act: GuardDo.stopAndClose, why: why));
            out.add((rule: r, act: GuardDo.giveUp, why: '$why; за час уже ${r.restarts.length} перезапуска — сдаюсь'));
            st.phase = _Phase.off;
          } else {
            r.restarts.add(now);
            out.add((rule: r, act: GuardDo.stopAndClose, why: why));
            st
              ..phase = _Phase.closing
              ..since = now
              ..missing = null
              ..hung = null;
          }
        case _Phase.closing:
          if (now.difference(st.since!) >= guardClosePause) {
            out.add((rule: r, act: GuardDo.launch, why: 'запуск ${r.process}'));
            st
              ..phase = _Phase.starting
              ..since = now;
          }
        case _Phase.starting:
          if (s.running && !s.hung) {
            st
              ..phase = _Phase.loading
              ..since = now;
          } else if (now.difference(st.since!) >= guardStartTimeout) {
            out.add((rule: r, act: GuardDo.giveUp, why: '${r.process} не запустилась за ${guardStartTimeout.inMinutes} мин'));
            st.phase = _Phase.off;
          }
        case _Phase.loading:
          if (!s.running) {
            // closed again while loading: start once more (counts as a restart)
            st
              ..phase = _Phase.watch
              ..missing = now.subtract(guardMissing);
          } else if (now.difference(st.since!).inSeconds >= r.loadSec && !scriptBusy) {
            out.add((rule: r, act: GuardDo.runScript, why: '${r.process} снова работает'));
            st
              ..phase = _Phase.watch
              ..since = null;
          }
        case _Phase.off:
          break; // handled above
      }
    }
    return out;
  }
}
