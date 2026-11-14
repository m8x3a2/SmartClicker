// Automatic starts: by schedule and when a program opens or becomes active.
part of 'app_controller.dart';

extension AppControllerAutorun on AppController {
  void saveSchedule() {
    writeJson(paths.scheduleFile, schedule.map((t) => t.toJson()).toList());
    _changed();
  }

  void addTask(ScheduleTask t) {
    schedule.add(t);
    saveSchedule();
  }

  void removeTask(ScheduleTask t) {
    schedule.remove(t);
    saveSchedule();
  }

  void saveAutoRules() {
    writeJson(paths.autorunFile, autoRules.map((r) => r.toJson()).toList());
    _changed();
  }

  void addAutoRule(AutoRule r) {
    autoRules.add(r);
    saveAutoRules();
  }

  void removeAutoRule(AutoRule r) {
    autoRules.remove(r);
    if (identical(_autoOwner, r)) _autoOwner = null;
    saveAutoRules();
  }

  /// Open programs (one window each) to choose from in a rule.
  List<WindowInfo> otherWindows() {
    final own = pid; // this process
    final seen = <String>{};
    return [
      for (final w in backend.windows())
        if (w.pid != own &&
            w.title.trim().isNotEmpty &&
            !AppController._systemProcesses.contains(w.process.toLowerCase()) &&
            seen.add(w.process.toLowerCase()))
          w
    ];
  }

  void _checkAutorun() {
    if (autoRules.isEmpty || autoRules.every((r) => !r.enabled)) return;
    if (!isRunning) _autoOwner = null;
    final List<(AutoRule, AutoAction)> actions;
    try {
      actions = _autoWatch.check(autoRules, backend.windows(), backend.activeWindow(),
          idle: state == RunState.idle,
          owner: _autoOwner,
          ownerPaused: _autoPaused && state == RunState.paused);
    } catch (e, s) {
      ErrorJournal.record(e, s, where: 'autorun');
      return;
    }
    for (final (r, a) in actions) {
      switch (a) {
        case AutoAction.start:
          if (!store.exists(r.script)) {
            notify('Автозапуск', 'Скрипт "${r.script}" не найден — запуск пропущен',
                level: 'warn');
            continue;
          }
          r.lastRun = DateTime.now();
          saveAutoRules();
          notify('Автозапуск', '"${r.script}" — ${r.trigger == 'focus' ? 'окно активно' : 'программа запущена'}: ${r.target}');
          _autoOwner = r;
          _autoPaused = false;
          runByName(r.script, reason: '⚡ Автозапуск: ${r.describe()}').then((ok) {
            if (!ok && identical(_autoOwner, r)) _autoOwner = null;
          });
        case AutoAction.stop:
          _log('system', '⚡ «${r.target}» ${r.trigger == 'focus' ? 'больше не активно' : 'закрыта'} — останавливаю');
          stop();
        case AutoAction.pause:
          if (state == RunState.running) {
            _log('system', '⚡ Окно «${r.target}» не активно — пауза до его возвращения');
            togglePause();
            _autoPaused = true;
          }
        case AutoAction.resume:
          if (state == RunState.paused) {
            _log('system', '⚡ Окно «${r.target}» снова активно — продолжаю');
            togglePause();
          }
          _autoPaused = false;
      }
    }
  }

  void _checkSchedule() {
    if (schedule.isEmpty || state != RunState.idle) return;
    final now = DateTime.now();
    for (final t in schedule) {
      if (!t.isDue(now, _started)) continue;
      t.lastRun = now;
      if (t.mode == 'once') t.enabled = false; // done
      saveSchedule();
      if (!store.exists(t.script)) {
        notify('Расписание', 'Скрипт "${t.script}" не найден — запуск пропущен',
            level: 'warn');
        continue;
      }
      notify('Запуск по расписанию', '"${t.script}" (${t.describe()})');
      runByName(t.script, reason: '⏰ Запуск по расписанию: ${t.describe()}');
      return; // one script at a time
    }
  }
}
