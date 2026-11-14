// Checks a script before a run: syntax, unknown names, missing pictures,
// endless loops without a pause.

import 'ask_scan.dart';
import 'ast.dart';
import 'parser.dart';
import 'values.dart';
import 'picture_refs.dart';
import 'script_refs.dart';

/// A problem found in a script before it runs.
class Issue {
  final int line;
  final String message;

  /// An error stops the script for sure once it gets to [line]; a warning
  /// is a likely mistake.
  final bool error;
  const Issue(this.line, this.message, {this.error = true});

  @override
  String toString() => 'Строка $line: $message';
}

/// What the checker needs to know about the world around the script.
class CheckContext {
  /// Built-in functions and constants of the engine.
  final Set<String> builtins;

  /// Text of another script (for run_script), or null if there is none.
  final String? Function(String name) scriptSource;

  /// Whether a picture of the files folder exists.
  final bool Function(String name) imageExists;

  /// Names of all scripts (to warn about a short run_script name that
  /// fits several of them).
  final List<String> scriptNames;

  const CheckContext({
    required this.builtins,
    required this.scriptSource,
    required this.imageExists,
    this.scriptNames = const [],
  });
}


/// camelCase -> snake_case, so both spellings of a built-in are matched.
String _snake(String name) => name.replaceAllMapped(
    RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

/// Finds mistakes that can be seen without running the script: syntax,
/// unknown functions and names, missing pictures and scripts, endless loops
/// without a pause, exact comparison of recognised text.
List<Issue> checkScript(String source, CheckContext ctx) {
  final List<Stmt> program;
  try {
    program = parseProgram(source);
  } on ScriptError catch (e) {
    return [Issue(e.line, e.message)];
  }
  final c = _Checker(ctx);
  c.collect(program, {});
  c.report(program);
  c.issues.sort((a, b) => a.line.compareTo(b.line));
  return c.issues;
}

class _Checker {
  final CheckContext ctx;
  _Checker(this.ctx);

  final issues = <Issue>[];

  /// Every name the script (or a script it runs) ever defines.
  final known = <String>{};

  /// Names of the script's own functions.
  final functions = <String>{};

  /// Pictures the script makes itself with screenshot("name", ...).
  final made = <String>{};

  /// Calls whose callee is a plain name: those names are checked as
  /// functions, not as variables.
  final _callees = Set<Ident>.identity();
  final _withBlock = Set<Call>.identity(); // calls of `with_window(...) { }`

  static String? _literal(Expr? e) =>
      e is Lit && e.value is String ? e.value as String : null;

  static String? _calleeName(Call c) =>
      c.callee is Ident ? _snake((c.callee as Ident).name) : null;

  // --------------------------------------------------------------- pass 1

  /// Collects the names defined in [program] and in the scripts it runs.
  void collect(List<Stmt> program, Set<String> visited) {
    for (final s in program) {
      walkNode(s, (n) {
        switch (n) {
          case VarS():
            known.addAll(n.decls.map((d) => d.key));
          case FuncE():
            if (n.name != null) {
              known.add(n.name!);
              functions.add(n.name!);
            }
            known.addAll(n.params);
          case ForIn():
            known.add(n.name);
          case Try():
            if (n.errName != null) known.add(n.errName!);
          case Assign(target: Ident(:final name)):
            known.add(name);
          case Update(target: Ident(:final name)):
            known.add(name);
          case Call():
            final name = _calleeName(n);
            final arg = n.args.isEmpty ? null : _literal(n.args.first);
            if (arg == null) break;
            if (name == 'screenshot') made.add(arg.toLowerCase());
            if (name == 'run_script' && visited.add(arg)) {
              final src = ctx.scriptSource(arg);
              if (src == null) break;
              try {
                collect(parseProgram(src), visited);
              } on ScriptError {
                // That script's own errors are shown when it is checked.
              }
            }
          default:
            break;
        }
      });
    }
  }

  // --------------------------------------------------------------- pass 2

  bool _defined(String name) => known.contains(name) || ctx.builtins.contains(name);

  void report(List<Stmt> program) {
    for (final s in program) {
      walkNode(s, (n) {
        if (n is Call && n.callee is Ident) _callees.add(n.callee as Ident);
        if (n is WithS) _withBlock.add(n.call);
      });
    }
    for (final s in program) {
      walkNode(s, (n) {
        switch (n) {
          case Ident():
            if (_callees.contains(n) || _defined(n.name)) break;
            issues.add(Issue(n.line,
                "неизвестное имя '${n.name}' — переменная нигде не задаётся${_hint(n.name)}"));
          case Call():
            _call(n);
          case Binary(op: '==' || '!='):
            for (final side in [n.l, n.r]) {
              if (side is Call && _calleeName(side) == 'read_text') {
                issues.add(Issue(
                    n.line,
                    'read_text(...) ${n.op} "..." почти никогда не совпадёт точно: '
                    'распознавание ошибается в мелочах. Используйте text_in или wait_text',
                    error: false));
              }
            }
          case Repeat(count: null):
            _loop(n, n.body);
          case While(cond: Lit(value: true || 1)):
            _loop(n, n.body);
          default:
            break;
        }
      });
    }
  }

  void _call(Call n) {
    if (n.callee case Ident(:final name)) {
      if (!_defined(name)) {
        issues.add(Issue(n.line, "неизвестная функция '$name'${_hint(name)}"));
        return;
      }
    }
    final name = _calleeName(n);
    if (scopedCalls.contains(name) && !_withBlock.contains(n)) {
      issues.add(Issue(
          n.line,
          '$name пишется с блоком в фигурных скобках на той же строке: '
          '$name("окно") { ... } — без блока не действует'));
    }
    if (name == 'ask' && !known.contains(name) && askOfCall(n) == null) {
      issues.add(Issue(
          n.line,
          'ask: вопрос не покажется перед запуском — текст вопроса, значение по умолчанию '
          'и options должны быть записаны как есть ("Сколько?", 10, ["а", "б"]), '
          'а не вычисляться. Скрипт получит значение по умолчанию',
          error: false));
    }
    final arg = n.args.isEmpty ? null : _literal(n.args.first);
    if (name == null || arg == null || known.contains(name)) return;
    if (pictureReaders.contains(name) &&
        !made.contains(arg.toLowerCase()) &&
        !ctx.imageExists(arg)) {
      issues.add(Issue(n.line,
          'картинки "$arg" нет в папке files — вырежьте её (Инструменты → Выделить область) '
          'и сохраните под этим именем'));
    }
    if (name == 'run_script' && ctx.scriptSource(arg) == null) {
      issues.add(Issue(n.line, 'скрипта "$arg" нет'));
    } else if (name == 'run_script') {
      final same = ambiguousScriptName(arg, ctx.scriptNames);
      if (same.isNotEmpty) {
        final runs = resolveScriptName(arg, ctx.scriptNames);
        issues.add(Issue(
            n.line,
            'run_script("$arg"): так называются несколько скриптов — '
            '${same.map((s) => '"$s"').join(', ')}; будет запущен "$runs". '
            'Напишите путь полностью: run_script("$runs")',
            error: false));
      }
    }
  }

  /// An endless loop with nothing in it that waits: thousands of clicks a
  /// second.
  void _loop(Node loop, Stmt body) {
    var calm = false;
    walkNode(body, (n) {
      if (calm) return;
      switch (n) {
        case Break() || Return() || Throw():
          calm = true;
        case Call():
          final name = _calleeName(n);
          if (name == null ||
              functions.contains(name) || // own function: may wait inside
              name.startsWith('wait') ||
              const {'sleep', 'delay', 'exit', 'stop', 'run_script', 'pause'}
                  .contains(name) ||
              n.named.containsKey('timeout')) {
            calm = true;
          }
        default:
          break;
      }
    });
    if (!calm) {
      issues.add(Issue(
          loop.line,
          'бесконечный цикл без паузы — добавьте внутрь wait(), иначе он будет '
          'кликать тысячи раз в секунду',
          error: false));
    }
  }

  /// " — может быть, click?" for a near miss, or ''.
  String _hint(String name) {
    final all = {...known, ...ctx.builtins}; // own names win a tie
    final lower = name.toLowerCase();
    for (final c in all) {
      if (c.toLowerCase() == lower) return ' — может быть, $c?';
    }
    String? best;
    var bestD = name.length <= 4 ? 2 : 3;
    for (final c in all) {
      if ((c.length - name.length).abs() >= bestD) continue;
      final d = _distance(lower, c.toLowerCase());
      if (d < bestD) {
        bestD = d;
        best = c;
      }
    }
    return best == null ? '' : ' — может быть, $best?';
  }

  static int _distance(String a, String b) {
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost]
            .reduce((x, y) => x < y ? x : y);
      }
      prev = cur;
    }
    return prev[b.length];
  }
}
