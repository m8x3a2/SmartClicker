// Guard against self-destruction inside the engine: switching the computer
// off in a loop, ending the program or Windows itself, overwriting the data
// of the program (rules — core/system/safety.dart).
part of 'runtime.dart';

extension _RuntimeSafety on ScriptRuntime {
  /// The guard is on unless the settings turned it off.
  bool get _protect => cfg['selfProtect'] != false;

  static const _hint =
      'Выключить защиту: Настройки → Запуск → «Защита от самоуничтожения»';

  /// Before a script switches the computer off: refuses during the first
  /// minutes after Windows started and right after the previous time, then
  /// remembers this time in the journal.
  void _guardPower(CallCtx c, String fn, String what) {
    if (!_protect || dryRun) return;
    final path = cfg['safetyFile'] as String?;
    final journal = path == null ? null : SafetyJournal.load(path);
    final reason = powerBlockReason(
        uptimeMs: backend.uptimeMs(),
        recent: journal?.power ?? const [],
        now: DateTime.now());
    if (reason != null) {
      c.fail('$fn: защита от самоуничтожения не дала $what — $reason. $_hint');
    }
    if (journal != null) {
      journal.power.add(DateTime.now());
      journal.save();
    }
  }

  void _guardKill(CallCtx c, String query) {
    if (!_protect) return;
    final name = protectedProcess(query);
    if (name == null) return;
    c.fail(name == 'smart_clicker'
        ? 'kill_process: скрипт не может закрыть сам SmartClicker (остановить скрипт — stop())'
        : 'kill_process("$query"): «$name» — часть Windows, без неё пропадёт рабочий стол или '
            'ввод; защита от самоуничтожения не даёт её завершить. $_hint');
  }

  void _guardWrite(CallCtx c, String fn, String path) {
    if (!_protect) return;
    final exe = Platform.resolvedExecutable;
    final cut = exe.lastIndexOf(Platform.pathSeparator);
    final files = cfg['filesDir'] as String? ?? '';
    final data = cfg['dataDir'] as String? ?? '';
    final reason = protectedWrite(path,
        dataDir: data, filesDir: files, exeDir: cut > 0 ? exe.substring(0, cut) : '');
    if (reason != null) {
      c.fail('$fn("$path"): $reason — защита от самоуничтожения. $_hint');
    }
  }
}
