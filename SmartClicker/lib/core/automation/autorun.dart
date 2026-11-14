// Rules "start a script when a program opens / its window becomes active"
// and their checking (pure logic, no timers).

import '../../platform/backend.dart';

/// "Profile": a script tied to a program. It starts by itself when the
/// program starts (its window appears) or when its window becomes active,
/// and may be stopped or paused when the program goes away.
class AutoRule {
  String script;

  /// Which program: process name ("game.exe" or "game"), part of a window
  /// title, or "process|title part" — as in use_window().
  String target;

  /// 'start' — the program's window appeared; 'focus' — it became active.
  String trigger;

  /// What to do when it goes away (closed / not active any more):
  /// 'none', 'stop', or 'pause' (only for 'focus': resume when it is
  /// active again).
  String leave;
  bool enabled;
  DateTime? lastRun;

  AutoRule({
    required this.script,
    required this.target,
    this.trigger = 'start',
    this.leave = 'stop',
    this.enabled = true,
    this.lastRun,
  });

  factory AutoRule.fromJson(Map j) {
    final trigger = j['trigger'] == 'focus' ? 'focus' : 'start';
    var leave = '${j['leave']}';
    if (!const {'none', 'stop', 'pause'}.contains(leave)) leave = 'stop';
    if (leave == 'pause' && trigger != 'focus') leave = 'stop';
    return AutoRule(
      script: '${j['script']}',
      target: '${j['target'] ?? ''}',
      trigger: trigger,
      leave: leave,
      enabled: j['enabled'] != false,
      lastRun: DateTime.tryParse('${j['lastRun']}'),
    );
  }

  Map<String, Object?> toJson() => {
        'script': script,
        'target': target,
        'trigger': trigger,
        'leave': leave,
        'enabled': enabled,
        'lastRun': lastRun?.toIso8601String(),
      };

  String describe() {
    final when = trigger == 'focus'
        ? 'когда окно «$target» становится активным'
        : 'когда запускается «$target»';
    final away = switch (leave) {
      'stop' => trigger == 'focus'
          ? '; остановить, когда окно не активно'
          : '; остановить, когда программа закрыта',
      'pause' => '; пауза, пока окно не активно',
      _ => '',
    };
    return '$when$away';
  }
}

/// What the controller should do for a rule.
enum AutoAction { start, stop, pause, resume }

class _Seen {
  bool fired;
  _Seen(this.fired);
}

/// Watches the programs once a second and decides what to start, stop,
/// pause or resume. Holds no timers: the controller calls [check].
class AutoWatch {
  final Map<AutoRule, _Seen> _seen = Map.identity();

  /// Whether the program of [rule] is there right now.
  static bool present(AutoRule rule, List<WindowInfo> windows, WindowInfo? active) {
    if (rule.target.trim().isEmpty) return false;
    return rule.trigger == 'focus'
        ? active != null && active.matches(rule.target)
        : windows.any((w) => w.matches(rule.target));
  }

  /// [idle] — nothing runs or records; [owner] — the rule whose script is
  /// running now (started by this watcher); [ownerPaused] — that script was
  /// paused by the watcher.
  List<(AutoRule, AutoAction)> check(
    List<AutoRule> rules,
    List<WindowInfo> windows,
    WindowInfo? active, {
    required bool idle,
    AutoRule? owner,
    bool ownerPaused = false,
  }) {
    final out = <(AutoRule, AutoAction)>[];
    _seen.removeWhere((r, _) => !rules.contains(r));
    var startedOne = false;
    for (final r in rules) {
      final here = r.enabled && present(r, windows, active);
      final seen = _seen[r];
      if (seen == null) {
        // First look: a program that is already open does not count as
        // "just started" — nothing should start by surprise.
        _seen[r] = _Seen(here && r.trigger == 'start');
        if (!(here && r.trigger == 'focus')) continue;
      }
      final s = _seen[r]!;
      final mine = identical(owner, r);
      if (here) {
        if (mine) {
          s.fired = true;
          if (ownerPaused && r.leave == 'pause') out.add((r, AutoAction.resume));
        } else if (!s.fired && idle && !startedOne) {
          s.fired = true;
          startedOne = true;
          out.add((r, AutoAction.start));
        }
      } else {
        s.fired = false;
        if (mine && r.enabled) {
          if (r.leave == 'stop') out.add((r, AutoAction.stop));
          if (r.leave == 'pause' && !ownerPaused) out.add((r, AutoAction.pause));
        }
      }
    }
    return out;
  }
}
