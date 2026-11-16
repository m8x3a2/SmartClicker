// use("Общее/бой"): loading a connected script — only its functions and
// top-level variables (and the scripts it uses itself); the rest of its code
// is a place for a test and does not run.
part of 'runtime.dart';

extension _RuntimeUse on ScriptRuntime {
  Future<Env> _loadLibrary(String name, String source) async {
    if (_libraries.length >= 50) {
      throw ScriptError('use: подключено слишком много скриптов (больше 50)', _line);
    }
    final List<Stmt> program;
    try {
      program = parseProgram(source, script: name);
    } on ScriptError catch (e) {
      e.script ??= name;
      e.placed = true;
      rethrow;
    }
    // Remembered before running: a script that uses this one back (A → B → A)
    // gets the functions already declared instead of an endless loop.
    final env = _libraries[name] = Env(interp.globals, script: name);
    for (final s in program) {
      if (s is FuncDecl) env.define(s.fn.name!, UserFn(s.fn, env));
    }
    final outer = _useTarget;
    _useTarget = env;
    enterScript(name);
    try {
      for (final s in program) {
        if (s is VarS || _isUse(s)) await interp.exec(s, env);
      }
    } finally {
      leaveScript();
      _useTarget = outer;
    }
    return env;
  }

  /// A statement `use("…")` (a script that connects others itself).
  static bool _isUse(Stmt s) =>
      s is ExprS && s.e is Call && (s.e as Call).callee is Ident && ((s.e as Call).callee as Ident).name == 'use';
}
