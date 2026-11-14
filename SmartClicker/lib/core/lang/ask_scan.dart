// Questions of a script: ask("Сколько раз?", 10). Found in the text before
// the run (one window for all of them), and the kind of field each needs.

import 'ast.dart';
import 'parser.dart';

/// What field a question needs; taken from the default value.
enum AskKind { number, text, flag, choice }

/// One question of a script.
class AskSpec {
  final String prompt;
  final AskKind kind;

  /// Default answer: a number, a text, true/false or one of [options].
  final Object? def;

  /// Choices of a [AskKind.choice] question.
  final List<Object?> options;
  final int line;
  const AskSpec(this.prompt, this.kind, this.def,
      {this.options = const [], this.line = 0});

  /// Whether [v] is a proper answer to this question; a remembered answer
  /// that no longer fits (the question was changed) is not used.
  bool fits(Object? v) => switch (kind) {
        AskKind.number => v is num,
        AskKind.text => v is String,
        AskKind.flag => v is bool,
        AskKind.choice => options.contains(v),
      };

  /// The answer to use: [remembered] if it still fits, else the default.
  Object? pick(Object? remembered) => fits(remembered) ? remembered : def;
}

/// Kind and default of a question from the values of its arguments: a list
/// of [options] (or a list as the default) gives a choice, true/false a
/// flag, a number a number field, anything else a text field.
AskSpec askSpec(String prompt, Object? def, Object? options, {int line = 0}) {
  final list = options is List && options.isNotEmpty
      ? options
      : (def is List && def.isNotEmpty ? def : null);
  if (list != null) {
    final chosen = list.contains(def) ? def : list.first;
    return AskSpec(prompt, AskKind.choice, chosen,
        options: List.unmodifiable(list), line: line);
  }
  return switch (def) {
    bool() => AskSpec(prompt, AskKind.flag, def, line: line),
    num() => AskSpec(prompt, AskKind.number, def, line: line),
    String() => AskSpec(prompt, AskKind.text, def, line: line),
    _ => AskSpec(prompt, AskKind.text, def == null ? '' : '$def', line: line),
  };
}

bool _isAsk(Call c) => c.callee is Ident && (c.callee as Ident).name == 'ask';

/// Argument [i] of an ask call, or the named one.
Expr? _arg(Call c, int i, String name) =>
    i < c.args.length ? c.args[i] : c.named[name];

const _notConst = Object();

/// Value of an expression written as a plain constant (`10`, `-5`, `"a"`,
/// `true`, `["a", "b"]`), otherwise [_notConst].
Object? _constant(Expr? e) {
  switch (e) {
    case null:
      return null;
    case Lit(:final value) when value == null || value is num || value is String || value is bool:
      return value;
    case Unary(op: '-', e: Lit(value: final num v)):
      return -v;
    case ArrayE(:final items):
      final out = <Object?>[];
      for (final i in items) {
        final v = _constant(i);
        if (identical(v, _notConst) || v is List) return _notConst;
        out.add(v);
      }
      return out;
    default:
      return _notConst;
  }
}

/// The question of an ask call, or null when its text or default is
/// computed while running (then no window can show it beforehand).
AskSpec? askOfCall(Call c) {
  final prompt = _constant(_arg(c, 0, 'text'));
  final def = _constant(_arg(c, 1, 'default'));
  final options = _constant(_arg(c, 2, 'options'));
  if (prompt is! String || identical(def, _notConst) || identical(options, _notConst)) {
    return null;
  }
  return askSpec(prompt, def, options, line: c.line);
}

/// Calls of ask in [program] whose question cannot be shown beforehand.
List<int> dynamicAskLines(List<Stmt> program) {
  final lines = <int>[];
  for (final s in program) {
    walkNode(s, (n) {
      if (n is Call && _isAsk(n) && askOfCall(n) == null) lines.add(n.line);
    });
  }
  return lines;
}

/// Questions of [source] in the order they appear, then those of the
/// scripts it runs with run_script("name") ([scriptSource] gives their
/// text). The same text twice is one question. A script with a syntax
/// error has none.
List<AskSpec> findAsks(String source, [String? Function(String name)? scriptSource]) {
  final seen = <String>{};
  final asks = <AskSpec>[];
  final visited = <String>{};
  void scan(String text) {
    final List<Stmt> program;
    try {
      program = parseProgram(text);
    } catch (_) {
      return;
    }
    final called = <String>[];
    for (final s in program) {
      walkNode(s, (n) {
        if (n is! Call || n.callee is! Ident) return;
        final name = (n.callee as Ident).name;
        if (name == 'ask') {
          final a = askOfCall(n);
          if (a != null && seen.add(a.prompt)) asks.add(a);
        } else if ((name == 'run_script' || name == 'runScript') && n.args.isNotEmpty) {
          if (n.args.first case Lit(value: final String other)) called.add(other);
        }
      });
    }
    for (final other in called) {
      final src = scriptSource?.call(other);
      if (src != null && visited.add(other)) scan(src);
    }
  }

  scan(source);
  return asks;
}

/// Answers for [asks]: the remembered ones that still fit, else defaults.
Map<String, Object?> defaultAnswers(List<AskSpec> asks, Map<String, Object?> remembered) =>
    {for (final a in asks) a.prompt: a.pick(remembered[a.prompt])};

/// Text of an answer for the log: `Сколько раз? = 200`.
String describeAnswers(Map<String, Object?> answers) => answers.entries
    .map((e) => '${e.key} = ${switch (e.value) {
          true => 'да',
          false => 'нет',
          String s => '"$s"',
          final v => '$v',
        }}')
    .join(' · ');
