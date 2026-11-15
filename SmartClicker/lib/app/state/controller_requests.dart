// Control from outside: `smart_clicker.exe --run "Скрипт"` / `--stop` (a
// neural network, a .bat file, the Windows Task Scheduler) and the state of
// the running script in files\state.json for other programs to read.
part of 'app_controller.dart';

/// Start parameters: run a script / stop the running one.
const runArg = '--run';
const stopArg = '--stop';

/// What the command line asks: {'run': name} or {'stop': true}, or null.
Map<String, Object?>? requestFromArgs(List<String> args) {
  final i = args.indexOf(runArg);
  if (i >= 0 && i + 1 < args.length && args[i + 1].trim().isNotEmpty) {
    return {'run': args[i + 1].trim()};
  }
  if (args.contains(stopArg)) return {'stop': true};
  return null;
}

/// Leaves a request for the copy of the program that is already open
/// (it reads the folder `requests` every second). Written whole: a reader
/// never sees half a file.
void sendRequest(AppPaths paths, Map<String, Object?> request) {
  final dir = Directory(paths.requests)..createSync(recursive: true);
  final id = '${DateTime.now().microsecondsSinceEpoch}-$pid';
  final tmp = File('${dir.path}${Platform.pathSeparator}$id.tmp');
  tmp.writeAsStringSync(jsonEncode({...request, 'at': DateTime.now().toIso8601String()}));
  tmp.renameSync('${dir.path}${Platform.pathSeparator}$id.json');
}

extension AppControllerRequests on AppController {
  /// A request that came with the start of this very copy.
  void queueRequest(Map<String, Object?> request) =>
      _requests.add((request, DateTime.now()));

  void maybeQueue(Map<String, Object?>? request) {
    if (request != null) queueRequest(request);
  }

  /// Called from the poll every second.
  void _checkRequests() {
    try {
      final dir = Directory(paths.requests);
      if (dir.existsSync()) {
        final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
          ..sort((a, b) => a.path.compareTo(b.path));
        for (final f in files) {
          Object? r;
          try {
            r = jsonDecode(f.readAsStringSync());
          } catch (_) {}
          try {
            f.deleteSync();
          } catch (_) {}
          if (r is Map) queueRequest(Map<String, Object?>.from(r));
        }
      }
    } catch (e, s) {
      ErrorJournal.record(e, s, where: 'requests');
    }
    if (_requests.isEmpty) return;
    final (r, at) = _requests.first;
    if (!settings.allowExternalRun) {
      _requests.removeAt(0);
      notify('Запуск извне выключен',
          'Другая программа попросила ${r['stop'] == true ? 'остановить скрипт' : 'запустить «${r['run']}»'}. '
              'Разрешить: Настройки → Запуск → «Разрешить запуск скриптов извне»',
          level: 'warn');
      return;
    }
    if (r['stop'] == true) {
      _requests.removeAt(0);
      if (busy) {
        _log('system', '⤴ Остановка извне (--stop)');
        stop();
      }
      return;
    }
    final want = '${r['run'] ?? ''}';
    final name = resolveScriptName(want, scripts);
    if (name == null) {
      _requests.removeAt(0);
      notify('Запуск извне', 'Скрипт «$want» не найден', level: 'warn');
      return;
    }
    if (safeMode) {
      _requests.removeAt(0);
      notify('Запуск извне', '«$name» не запущен: безопасный режим', level: 'warn');
      return;
    }
    // Waits while automation is held back or another script works — not
    // longer than 10 minutes.
    if (!automationOn || busy) {
      if (DateTime.now().difference(at).inMinutes >= 10) {
        _requests.removeAt(0);
        notify('Запуск извне', '«$name» не запущен: 10 минут было занято', level: 'warn');
      }
      return;
    }
    _requests.removeAt(0);
    notify('Запуск извне', '«$name»');
    runByName(name, reason: '⤴ Запуск извне ($runArg)');
  }

  /// The state of the running script for other programs (files\state.json),
  /// once a second while it works and once at the end.
  void _writeState({String? status, String? error}) {
    if (!settings.stateFile) return;
    final name = _runScript;
    if (name == null) return;
    final sep = Platform.pathSeparator;
    final path = '${paths.files}${sep}state.json';
    try {
      final tmp = File('$path.tmp')..parent.createSync(recursive: true);
      tmp.writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
        'script': name,
        'status': status ?? (state == RunState.paused ? 'paused' : 'running'),
        'line': _runLine,
        'started': _runStarted?.toIso8601String(),
        'updated': DateTime.now().toIso8601String(),
        'error': error,
        'vars': {for (final v in vars.value) if (v.scope.isEmpty) v.name: v.value},
      }));
      tmp.renameSync(path);
    } catch (e, s) {
      ErrorJournal.record(e, s, where: 'state.json');
    }
  }
}
