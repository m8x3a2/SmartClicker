// "Run every script of a folder without clicks": the scripts go one after
// another in test mode with a time limit, then one summary (for the folder
// "Проверки" — compared with what each check is expected to do).
part of 'app_controller.dart';

/// How one script of a dry run of a folder ended.
class BatchResult {
  final String script;

  /// ok | limit | error | stopped | killed
  final String status;
  final int ms;
  final String? error;
  final int line;

  /// Actions the script would have done (clicks, keys…) and warnings.
  final int actions, warnings;

  /// The last line the script wrote to the log (what to look at).
  final String lastLog;

  /// What a check script of the folder "Проверки" is expected to end with;
  /// null for other scripts.
  final String? expected;
  const BatchResult(
    this.script,
    this.status,
    this.ms, {
    this.error,
    this.line = 0,
    this.actions = 0,
    this.warnings = 0,
    this.lastLog = '',
    this.expected,
  });

  /// Ended the way it should (or, without an expectation, without an error).
  bool get fine => expected != null ? expected == status : status == 'ok' || status == 'limit';

  String get statusLabel => switch (status) {
    'ok' => 'завершён',
    'limit' => 'остановлен по лимиту',
    'error' => 'ошибка',
    'stopped' => 'остановлен',
    _ => 'не отвечал',
  };

  String describe() =>
      '${fine ? '✔' : '✖'} $script — $statusLabel за ${(ms / 1000).toStringAsFixed(1)} с'
      '${actions > 0 ? ', действий: $actions' : ''}${warnings > 0 ? ', предупреждений: $warnings' : ''}'
      '${error != null ? '\n    ошибка${line > 0 ? ' (строка $line)' : ''}: $error' : ''}'
      '${expected != null && !fine ? '\n    ожидалось: ${BatchResult(script, expected!, 0).statusLabel}' : ''}'
      '${lastLog.isNotEmpty ? '\n    последнее в логе: $lastLog' : ''}';
}

/// The summary of a dry run of a folder.
class BatchSummary {
  final String folder;
  final List<BatchResult> results;
  final bool cancelled;
  const BatchSummary(this.folder, this.results, {this.cancelled = false});

  String asText() =>
      'Прогон папки «$folder» без кликов${cancelled ? ' (прерван)' : ''}\n\n'
      '${results.map((r) => r.describe()).join('\n')}\n\n'
      'Хорошо: ${results.where((r) => r.fine).length} из ${results.length}';
}

extension AppControllerBatch on AppController {
  /// Seconds each script of a dry run may work.
  static const batchLimitSec = 20;

  bool get batchRunning => _batch != null;

  /// Runs every script of [folder] (with subfolders) one after another in
  /// test mode: nothing is clicked or pressed, each gets [batchLimitSec].
  Future<void> runFolderDry(String folder) async {
    if (busy) return;
    final names = scriptsIn(folder)..sort();
    if (names.isEmpty) return;
    _batchCancelled = false;
    logs.clear();
    errorLine.value = 0;
    state = RunState.running;
    _log(
      'system',
      '▶ Прогон папки «$folder» без кликов: скриптов ${names.length}, до $batchLimitSec с на каждый. '
          'Стоп — ${settings.stopKeysLabel}',
    );
    _changed();
    final all = _allScriptTexts();
    final results = <BatchResult>[];
    for (var i = 0; i < names.length && !_batchCancelled; i++) {
      final name = names[i];
      _log('system', '— ${i + 1}/${names.length}: «$name»');
      final source = all[name] ?? '';
      final answers = defaultAnswers(questionsOf(source), rememberedAnswers(name));
      results.add(await _dryRun(name, source, answers));
      _log(results.last.fine ? 'system' : 'warn', results.last.describe().split('\n').first);
    }
    _batch = null;
    state = RunState.idle;
    backend.releaseAll();
    _log(
      'system',
      '■ Прогон окончен: хорошо ${results.where((r) => r.fine).length} из ${results.length}',
    );
    batchSummary.value = BatchSummary(folder, results, cancelled: _batchCancelled);
    _changed();
  }

  Future<BatchResult> _dryRun(String name, String source, Map<String, Object?> answers) {
    final done = Completer<BatchResult>();
    var actions = 0, warnings = 0;
    var last = '';
    final sw = Stopwatch()..start();
    final expected = name.startsWith('$checksFolder/')
        ? checkExpectations[ScriptStore.baseOf(name)]
        : null;
    final runner = ScriptRunner((e) {
      switch (e['t']) {
        case 'log':
          final lv = '${e['lv']}';
          if (lv == 'action') actions++;
          if (lv == 'warn') warnings++;
          if (lv == 'info' || lv == 'warn') last = '${e['m']}';
        case 'done':
          if (!done.isCompleted) {
            done.complete(
              BatchResult(
                name,
                '${e['status']}',
                (e['ms'] as num?)?.toInt() ?? sw.elapsedMilliseconds,
                error: e['status'] == 'limit' ? null : e['error'] as String?, // the limit is expected
                line: (e['line'] as num?)?.toInt() ?? 0,
                actions: actions,
                warnings: warnings,
                lastLog: last,
                expected: expected,
              ),
            );
          }
      }
    });
    _batch = runner;
    final cfg = {
      ..._engineConfig(name, source, answers),
      'step': false,
      'breaks': const <int>[],
      'watch': false,
      'showClicks': false,
      'dryRun': true,
      'allowPower': false,
      'maxRuntimeMs': AppControllerBatch.batchLimitSec * 1000,
    };
    runner.start(cfg).catchError((Object err) {
      if (!done.isCompleted) done.complete(BatchResult(name, 'error', 0, error: '$err'));
    });
    return done.future;
  }

  void _cancelBatch() {
    _batchCancelled = true;
    _log('system', '⏹ Прогон прерван');
    _batch?.stop(grace: const Duration(milliseconds: 150));
  }
}
