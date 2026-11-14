// Questions of a script (ask): the window before a run, the last answers
// of every script (answers.json), what a run without the window gets.
part of 'app_controller.dart';

/// Shows the questions of [script] and gives the answers, or null when the
/// user cancelled the run. Set by the interface (it has the BuildContext).
typedef AskHandler = Future<Map<String, Object?>?> Function(
    String script, List<AskSpec> asks, Map<String, Object?> initial);

extension AppControllerAsk on AppController {
  /// Questions of [source] and of the scripts it runs.
  List<AskSpec> questionsOf(String source) {
    final all = _allScriptTexts();
    return findAsks(source, (n) => all[resolveScriptName(n, all.keys)]);
  }

  /// Remembered answers of [script] (prompt → answer).
  Map<String, Object?> rememberedAnswers(String script) =>
      Map<String, Object?>.from((answers[script] as Map?) ?? const {});

  /// Answers for a run of [script]. With [interactive] the window is shown
  /// (null — the user cancelled); otherwise the last answers or defaults.
  Future<Map<String, Object?>?> _answersFor(String script, String source,
      {required bool interactive}) async {
    final asks = questionsOf(source);
    if (asks.isEmpty) return const {};
    final initial = defaultAnswers(asks, rememberedAnswers(script));
    final handler = askHandler;
    if (!interactive || handler == null || compact || hiddenToTray) return initial;
    final got = await handler(script, asks, initial);
    if (got == null) return null;
    _rememberAnswers(script, got);
    return got;
  }

  /// Questions of [script] and the answers it would get now (for the window
  /// "Answers to the questions" of the script list).
  (List<AskSpec>, Map<String, Object?>) answersOf(String script) {
    final text = script == current ? editor.text : (buffers[script] ?? store.read(script));
    final asks = questionsOf(text);
    return (asks, defaultAnswers(asks, rememberedAnswers(script)));
  }

  /// Saves answers chosen without a run: the schedule, the keys of scripts
  /// and the mini panel use them next time.
  void saveAnswers(String script, Map<String, Object?> got) {
    _rememberAnswers(script, got);
    notify('Ответы сохранены', '«$script»: ${describeAnswers(got)}', level: 'ok');
  }

  /// Runs [script] with the window of its questions, wherever it was
  /// started from (the "?" of the mini panel, Shift + the key of a script):
  /// the program window comes forward for the questions. Without questions
  /// it is an ordinary run.
  Future<void> runWithQuestions(String script) async {
    if (busy || !store.exists(script)) return;
    if (questionsOf(script == current ? editor.text : (buffers[script] ?? store.read(script)))
        .isEmpty) {
      await runByName(script);
      return;
    }
    if (compact) setCompact(false);
    restoreFromTray(); // also brings a minimized or covered window forward
    if (script != current) open(script);
    openPage('scripts');
    await run();
  }

  void _rememberAnswers(String script, Map<String, Object?> got) {
    answers[script] = {...rememberedAnswers(script), ...got};
    writeJson(paths.answersFile, answers);
  }

  /// The answers go with the script when it is renamed or moved.
  void _retargetAnswers(String old, String name) {
    final a = answers.remove(old);
    if (a == null) return;
    answers[name] = a;
    writeJson(paths.answersFile, answers);
  }

  void _forgetAnswers(Iterable<String> scripts) {
    var changed = false;
    for (final s in scripts) {
      changed = answers.remove(s) != null || changed;
    }
    if (changed) writeJson(paths.answersFile, answers);
  }
}
