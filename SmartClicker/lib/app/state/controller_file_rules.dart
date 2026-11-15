// Автозапуск «По файлу»: a script starts when a file changes (a neural
// network wrote a task). Asks first, runs in the test mode or just runs;
// waits while another script works or automation is held back. The rules
// and their checking — core/automation/file_watch.dart.
part of 'app_controller.dart';

extension AppControllerFileRules on AppController {
  void saveFileRules() {
    writeJson(paths.fileRulesFile, fileRules.map((r) => r.toJson()).toList());
    _changed();
  }

  void addFileRule(FileRule r) {
    fileRules.add(r);
    saveFileRules();
  }

  void removeFileRule(FileRule r) {
    fileRules.remove(r);
    _fileQueue.removeWhere((q) => identical(q.$1, r));
    if (fileAsk != null && identical(fileAsk!.$1, r)) fileAsk = null;
    saveFileRules();
  }

  /// Full path of the file of a rule (a bare name is in the files folder).
  String fileRulePath(String path) {
    final p = path.trim();
    final abs = p.startsWith('/') || p.startsWith(r'\') || RegExp(r'^[A-Za-z]:').hasMatch(p);
    return abs ? p : '${paths.files}${Platform.pathSeparator}$p';
  }

  static String _stampOf(String path) {
    try {
      final s = File(path).statSync();
      if (s.type == FileSystemEntityType.notFound) return '';
      return '${s.modified.microsecondsSinceEpoch}:${s.size}';
    } catch (_) {
      return '';
    }
  }

  /// The value at [key] ("a.b") of the JSON file is "yes": true, a number
  /// other than 0, a non-empty text or list.
  static bool _keyIsYes(String path, String key) {
    try {
      var text = File(path).readAsStringSync();
      if (text.startsWith('﻿')) text = text.substring(1);
      Object? v = jsonDecode(text);
      for (final part in key.split('.')) {
        if (v is Map) {
          v = v[part];
        } else if (v is List) {
          final i = int.tryParse(part);
          v = i != null && i >= 0 && i < v.length ? v[i] : null;
        } else {
          return false;
        }
      }
      return switch (v) {
        null => false,
        bool b => b,
        num n => n != 0,
        String s => s.isNotEmpty && s.toLowerCase() != 'false',
        List l => l.isNotEmpty,
        Map m => m.isNotEmpty,
        _ => true,
      };
    } catch (_) {
      return false;
    }
  }

  /// Called from the poll once a second.
  void _checkFileRules() {
    if (fileRules.isEmpty && _fileQueue.isEmpty && fileAsk == null) return;
    final now = DateTime.now();
    try {
      final events = _fileWatch.check(
          fileRules, (p) => _stampOf(fileRulePath(p)), (p, k) => _keyIsYes(fileRulePath(p), k), now);
      for (final (r, e) in events) {
        switch (e) {
          case FileEvent.fire:
            if (safeMode) {
              notify('Автозапуск по файлу', '«${r.path}» изменился, но «${r.script}» не запущен: безопасный режим',
                  level: 'warn');
            } else if (!_fileQueue.any((q) => identical(q.$1, r))) {
              _fileQueue.add((r, r.mode, now));
            }
          case FileEvent.tooSoon:
            _log('warn', '📄 «${r.path}» изменился, но «${r.script}» запускался меньше ${r.minGapSec} с назад — пропуск');
          case FileEvent.notReady:
            break;
        }
      }
    } catch (e, s) {
      ErrorJournal.record(e, s, where: 'file rules');
    }
    _runFileQueue(now);
  }

  void _runFileQueue(DateTime now) {
    final ask = fileAsk;
    if (ask != null) {
      // Nobody answered in a minute: not run (the safe choice).
      if (now.difference(ask.$2).inSeconds >= 60) {
        fileAsk = null;
        _log('warn', '📄 Нет ответа — «${ask.$1.script}» не запущен');
        _changed();
      }
      return;
    }
    if (_fileQueue.isEmpty) return;
    final (rule, mode, since) = _fileQueue.first;
    if (!fileRules.contains(rule) || !store.exists(rule.script)) {
      _fileQueue.removeAt(0);
      notify('Автозапуск по файлу', 'Скрипт «${rule.script}» не найден — запуск пропущен', level: 'warn');
      return;
    }
    // Waits while another script works or automation is held back.
    if (!automationOn || busy) {
      if (now.difference(since).inMinutes >= 10) {
        _fileQueue.removeAt(0);
        notify('Автозапуск по файлу', '«${rule.script}» не запущен: 10 минут было занято', level: 'warn');
      }
      return;
    }
    _fileQueue.removeAt(0);
    if (mode == FileRunMode.ask) {
      fileAsk = (rule, now);
      notify('Файл изменился', '«${rule.path}» → запустить «${rule.script}»? Ответ — в полосе сверху окна');
      _changed();
      return;
    }
    _startFileRule(rule, dry: mode == FileRunMode.test);
  }

  void _startFileRule(FileRule rule, {required bool dry}) {
    rule.lastRun = DateTime.now();
    saveFileRules();
    notify('Автозапуск по файлу', '«${rule.script}»${dry ? ' (тестовый режим)' : ''}: изменился «${rule.path}»');
    runByName(rule.script, reason: '📄 Автозапуск по файлу: ${rule.describe()}', dry: dry);
  }

  /// The answer in the strip: run (for real or in the test mode) or not.
  void answerFileAsk({required bool run, bool dry = false}) {
    final ask = fileAsk;
    if (ask == null) return;
    fileAsk = null;
    if (run && !busy) {
      _startFileRule(ask.$1, dry: dry);
    } else {
      _log('system', '📄 «${ask.$1.script}» не запущен (отменено)');
    }
    _changed();
  }
}

extension AppControllerFilePick on AppController {
  /// The system "open file" window; a file in the files folder comes back
  /// as its bare name ("задание.json"), others as a full path.
  String? pickWatchedFile() {
    final path = backend.pickFile(save: false, title: 'Какой файл отслеживать', ext: '*');
    if (path == null) return null;
    final files = '${paths.files}${Platform.pathSeparator}';
    return path.toLowerCase().startsWith(files.toLowerCase()) ? path.substring(files.length) : path;
  }
}
