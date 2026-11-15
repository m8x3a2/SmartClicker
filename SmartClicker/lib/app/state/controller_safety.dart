// Safe mode and the delay of automation after a start with Windows: the
// schedule, autorun and restart after an error do not start anything until
// allowed. Rules and the journal — core/system/safety.dart.
part of 'app_controller.dart';

extension AppControllerSafety on AppController {
  /// Called once when the window is created. [safeArg] — `--safe`,
  /// [rescue] — what safe.txt / reset.txt asked for, [resetMoved] — the
  /// files reset.txt moved aside.
  void beginStart(
      {bool safeArg = false, RescueRequest? rescue, List<String> resetMoved = const []}) {
    final journal = SafetyJournal.load(paths.safetyFile);
    final now = DateTime.now();
    final loop = isCrashLoop(journal.launches, now);
    journal.launches.add(LaunchRecord(now));
    journal.save();
    _safety = journal;
    _purgeTrash(); // older than 30 days goes for good

    final reasons = <String>[
      if (safeArg) 'запуск с параметром --safe',
      if (backend.isUserKeyDown(0x10) || backend.isVkDown(0x10)) 'при запуске был зажат Shift',
      if (rescue != null && rescue.safe) 'найден файл safe.txt',
      if (rescue != null && rescue.reset)
        'найден reset.txt: настройки, расписание и автозапуск сброшены '
            '(старые лежат в папке rescue)',
      if (loop)
        'программа $crashLoopStarts раза подряд закрылась со сбоем за '
            '${crashLoopWindow.inMinutes} минуты',
    ];
    if (reasons.isNotEmpty) {
      safeMode = true;
      safeReason = reasons.join('; ');
      final moved = resetMoved.isEmpty ? '' : ' Перенесено: ${resetMoved.join(', ')}.';
      Timer.run(() => notify('Безопасный режим',
          'Расписание, автозапуск и перезапуск после ошибки ничего не запускают сами: '
          '$safeReason.$moved Выйти — кнопкой в полосе сверху',
          level: 'warn'));
    } else if (startedWithWindows && settings.autostartDelaySec > 0) {
      automationHeldUntil = now.add(Duration(seconds: settings.autostartDelaySec));
      Timer.run(() => notify('Автоматика отложена',
          'SmartClicker запущен вместе с Windows: расписание и автозапуск включатся через '
          '${_delayText(settings.autostartDelaySec)}. Включить сразу или отменить — '
          'полоса сверху в окне программы'));
    }
    _changed();
  }

  /// Schedule, autorun and restart after an error may start scripts now.
  bool get automationOn {
    if (safeMode || automationOff) return false;
    final until = automationHeldUntil;
    if (until == null) return true;
    if (DateTime.now().isBefore(until)) return false;
    automationHeldUntil = null;
    _log('system', '▶ Автоматика включена (прошла задержка после запуска с Windows)');
    _changed();
    return true;
  }

  /// Seconds left until automation turns on by itself (0 — not waiting).
  int get automationWaitSec {
    final until = automationHeldUntil;
    if (until == null || safeMode || automationOff) return 0;
    final s = until.difference(DateTime.now()).inSeconds;
    return s < 0 ? 0 : s + 1;
  }

  /// Leaves safe mode / ends the delay: automation works from now on.
  void enableAutomationNow() {
    final was = safeMode;
    safeMode = false;
    safeReason = '';
    automationOff = false;
    automationHeldUntil = null;
    _log('system', was ? '▶ Безопасный режим выключен — автоматика работает'
        : '▶ Автоматика включена вручную');
    _changed();
  }

  /// "Do not turn on until the program restarts".
  void keepAutomationOff() {
    automationOff = true;
    automationHeldUntil = null;
    _log('system', '⏸ Автоматика выключена до перезапуска программы');
    _changed();
  }

  /// The program is closing normally (not a crash): the next start does not
  /// count towards a crash loop.
  void markCleanExit() {
    final j = _safety;
    if (j == null || j.launches.isEmpty) return;
    j.launches.last.clean = true;
    j.save();
  }

  static String _delayText(int sec) =>
      sec % 60 == 0 ? '${sec ~/ 60} мин' : sec < 60 ? '$sec с' : '${sec ~/ 60} мин ${sec % 60} с';
}
