// «Сторож»: while a script works, its program (a game) is watched; it crashed
// or hung — the script stops, the program is closed and started again, and
// after its window appears and loads, the script starts again. The rules and
// their checking — core/automation/game_guard.dart.
part of 'app_controller.dart';

extension AppControllerGuard on AppController {
  void saveGuardRules() {
    writeJson(paths.guardRulesFile, guardRules.map((r) => r.toJson()).toList());
    _changed();
  }

  void addGuardRule(GuardRule r) {
    guardRules.add(r);
    // the script already works: watch from now on
    if (isRunning && _runScript == r.script) _guardArmed.add(r);
    saveGuardRules();
  }

  void removeGuardRule(GuardRule r) {
    guardRules.remove(r);
    _guardArmed.remove(r);
    _guardStopping.remove(r);
    _guardWatch.reset(r);
    saveGuardRules();
  }

  /// The guard is stopping this script itself (the program crashed or hung).
  bool _stoppedByGuard(String script) => _guardStopping.any((r) => r.script == script);

  /// The script failed, and its guard will bring the program and the script
  /// back: it restarts the program now, or the program is gone or hung.
  bool _guardWillRestart(String script) {
    for (final r in guardRules) {
      if (!r.enabled || r.script != script || !_guardArmed.contains(r)) continue;
      if (_guardWatch.busy(r)) return true;
      final seen = _guardSeen(r);
      if (!seen.running || seen.hung) return true;
    }
    return false;
  }

  /// The rule watches its program now.
  bool guardWatching(GuardRule r) => _guardArmed.contains(r);

  /// A script starts (by any way): the rules of that script begin to watch.
  void _armGuards(String script) {
    for (final r in guardRules) {
      if (!r.enabled || r.script != script) continue;
      if (!_guardWatch.busy(r)) _guardWatch.reset(r);
      _guardArmed.add(r);
    }
  }

  /// A run ended. Stopped by the user or finished — the watching ends; an
  /// error may come from the crash itself, so the guard keeps watching; the
  /// stop made by the guard itself is not the user's.
  void _guardRunEnded(String script, String status) {
    for (final r in guardRules) {
      if (r.script != script) continue;
      if (_guardStopping.remove(r)) continue;
      if (status == 'error' || status == 'limit') continue;
      if (_guardArmed.remove(r)) _guardWatch.reset(r);
    }
  }

  /// What the program of a rule looks like: runs, its window does not respond.
  GuardSeen _guardSeen(GuardRule r) {
    final name = GuardRule.processName(r.process);
    final running = backend.processes().any((p) => p.toLowerCase() == name);
    var hung = false;
    if (running && r.hangSec > 0) {
      for (final w in backend.windows()) {
        if (w.process.toLowerCase() == name && backend.isHungWindow(w.handle)) {
          hung = true;
          break;
        }
      }
    }
    return (running: running, hung: hung);
  }

  /// Called from the poll once a second.
  void _checkGuards() {
    if (guardRules.isEmpty || _guardArmed.isEmpty && !guardRules.any(_guardWatch.busy)) return;
    try {
      final steps = _guardWatch.check(
        guardRules,
        (r) => _guardArmed.contains(r) && automationOn && !safeMode,
        _guardSeen,
        busy,
        DateTime.now(),
      );
      for (final s in steps) {
        _guardDo(s);
      }
    } catch (e, st) {
      ErrorJournal.record(e, st, where: 'guard');
    }
  }

  void _guardDo(GuardStep s) {
    final r = s.rule;
    final name = GuardRule.processName(r.process);
    switch (s.act) {
      case GuardDo.stopAndClose:
        final left = r.maxPerHour - r.restarts.length;
        _log('warn', '🛡 Сторож: ${s.why} — останавливаю «${r.script}»'
            '${r.launch.trim().isEmpty ? '' : ', перезапускаю (ещё можно $left раз за час)'}');
        notify('Сторож', '${s.why}. ${r.launch.trim().isEmpty ? 'Скрипт остановлен' : 'Перезапускаю программу и скрипт'}',
            level: 'warn');
        if (isRunning && _runScript == r.script) {
          _guardStopping.add(r);
          stop();
        }
        if (backend.processes().any((p) => p.toLowerCase() == name)) {
          final guarded = protectedProcess(name);
          if (guarded != null) {
            _log('error', '🛡 Сторож: $guarded — часть Windows или SmartClicker, закрывать не буду');
          } else {
            backend.killProcess(name);
          }
        }
        saveGuardRules(); // the restart is counted
      case GuardDo.launch:
        _log('system', '🛡 Сторож: запускаю ${r.launch}');
        _guardLaunch(r.launch.trim());
      case GuardDo.runScript:
        if (!store.exists(r.script)) {
          notify('Сторож', 'Скрипт «${r.script}» не найден — не запущен', level: 'warn');
          _guardArmed.remove(r);
          return;
        }
        notify('Сторож', '${s.why} — запускаю «${r.script}» снова');
        runByName(r.script, reason: '🛡 Сторож: ${s.why}', via: 'guard');
      case GuardDo.giveUp:
        _log('error', '🛡 Сторож сдался: ${s.why}');
        notify('Сторож сдался', '${s.why}. «${r.script}» не перезапускается', level: 'error');
        _guardArmed.remove(r);
        saveGuardRules();
    }
  }

  /// Starts a program: an exe, a shortcut or a link (steam://…), as the
  /// Explorer would.
  void _guardLaunch(String path) {
    if (!Platform.isWindows) return;
    Process.start('cmd', ['/c', 'start', '', path], mode: ProcessStartMode.detached).catchError((Object e) {
      _log('error', '🛡 Сторож: не удалось запустить $path: $e');
      return Process.start('cmd', ['/c', 'rem']);
    });
  }

  /// The system "open file" window for the program to start again.
  String? pickGuardProgram() =>
      backend.pickFile(save: false, title: 'Какую программу запускать снова', ext: '*');
}
