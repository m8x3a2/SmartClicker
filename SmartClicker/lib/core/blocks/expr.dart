// Expressions inside slots of blocks: what they look like and how to build them.

import '../lang/ast.dart';
import '../lang/lexer.dart';
import '../lang/parser.dart';
import '../lang/values.dart';
import 'blocks.dart' show callText;

/// What an expression in a slot of a block looks like; decides how the
/// slot is drawn. Parts are kept as source text.
sealed class XShape {
  const XShape();
}

/// Empty slot.
class XEmpty extends XShape {
  const XEmpty();
}

/// Number-like literal as written: `5`, `-1.5`, `50%`, `1s`, `800..1200`.
class XNum extends XShape {
  final String src;
  const XNum(this.src);
}

class XStr extends XShape {
  final String value;
  const XStr(this.value);
}

class XBool extends XShape {
  final bool value;
  const XBool(this.value);
}

class XNull extends XShape {
  const XNull();
}

class XVar extends XShape {
  final String name;
  const XVar(this.name);
}

class XCall extends XShape {
  final String name;
  final List<String> args;
  final Map<String, String> named;
  const XCall(this.name, this.args, this.named);
}

/// Binary operator: comparison, arithmetic, `&&`, `||`.
class XOp extends XShape {
  final String op;
  final String left;
  final String right;
  const XOp(this.op, this.left, this.right);
}

class XNot extends XShape {
  final String operand;
  const XNot(this.operand);
}

/// Anything else, or text that is not a valid expression.
class XRaw extends XShape {
  final String src;
  final bool valid;
  const XRaw(this.src, {this.valid = true});
}

/// Operators shown as operator blocks, by precedence level.
const opLevels = <String, int>{
  '||': 0, '??': 0, //
  '&&': 1,
  '==': 2, '!=': 2, '===': 2, '!==': 2,
  '<': 3, '<=': 3, '>': 3, '>=': 3,
  '+': 5, '-': 5,
  '*': 6, '/': 6, '%': 6,
};

({Expr expr, String Function(Expr) text, List<Token> tokens})? _parse(String src) {
  try {
    final tokens = Lexer(src).scan();
    final spans = Map<Node, (int, int)>.identity();
    final parser = Parser(tokens, spans: spans);
    final e = parser.expression();
    if (parser.cur.type != T.eof) return null;
    String text(Expr x) {
      final (a, b) = spans[x]!;
      return src.substring(tokens[a].start, tokens[b - 1].end);
    }

    return (expr: e, text: text, tokens: tokens);
  } on ScriptError {
    return null;
  }
}

bool _numLit(Expr e) =>
    (e is Lit && (e.value is num || e.value is Percent)) ||
    (e is Unary && e.op == '-' && e.e is Lit && (e.e as Lit).value is num);

/// The source is one complete expression.
bool isValidExpr(String src) => src.trim().isNotEmpty && _parse(src) != null;

/// Why [src] is not one complete expression, or null if it is.
String? exprError(String src) {
  if (src.trim().isEmpty) return 'Пусто';
  try {
    final parser = Parser(Lexer(src).scan());
    parser.expression();
    if (parser.cur.type != T.eof) return 'Лишнее после выражения: ${parser.cur}';
    return null;
  } on ScriptError catch (e) {
    return e.message;
  }
}

/// Why [src] is not valid code (statements), or null.
String? codeError(String src) {
  try {
    parseProgram(src);
    return null;
  } on ScriptError catch (e) {
    return 'Строка ${e.line}: ${e.message}';
  }
}

final _ident = RegExp(r'^[A-Za-z_$Ѐ-ӿ][A-Za-z0-9_$Ѐ-ӿ]*$');

/// A name that can be a variable or a function.
bool isIdentifier(String s) => _ident.hasMatch(s) && !keywords.contains(s);

XShape shapeOf(String src) {
  if (src.trim().isEmpty) return const XEmpty();
  final p = _parse(src);
  if (p == null) return XRaw(src, valid: false);
  final e = p.expr;
  if (_wrapped(p.tokens)) return XRaw(src);
  switch (e) {
    case Lit(value: final String v):
      return XStr(v);
    case Lit(value: final bool v):
      return XBool(v);
    case Lit(value: null) when src.trim() == 'null':
      return const XNull();
    case _ when _numLit(e):
      return XNum(src.trim());
    case RangeE(lo: final lo, hi: final hi) when _numLit(lo) && _numLit(hi):
      return XNum(src.trim());
    case Ident(name: final n):
      return XVar(n);
    case Call(callee: Ident(name: final n)):
      return XCall(n, [for (final a in e.args) p.text(a)],
          {for (final x in e.named.entries) x.key: p.text(x.value)});
    case Binary(op: final op, l: final l, r: final r) when opLevels.containsKey(op):
      return XOp(op, p.text(l), p.text(r));
    case Logical(op: final op, l: final l, r: final r):
      return XOp(op, p.text(l), p.text(r));
    case Unary(op: '!', e: final x):
      return XNot(p.text(x));
    default:
      return XRaw(src);
  }
}

/// The whole expression is in parentheses: `(a + b)`.
bool _wrapped(List<Token> t) {
  if (t.length < 3 || !t.first.isOp('(')) return false;
  var depth = 0;
  for (var i = 0; i < t.length - 1; i++) {
    if (t[i].isOp('(')) depth++;
    if (t[i].isOp(')')) {
      depth--;
      if (depth == 0) return i == t.length - 2;
    }
  }
  return false;
}

/// Precedence of an expression as an operand: higher binds tighter.
int _precedence(String src) {
  final p = _parse(src);
  if (p == null) return -1;
  if (_wrapped(p.tokens)) return 100;
  final e = p.expr;
  return switch (e) {
    Binary(op: final op) || Logical(op: final op) => opLevels[op] ?? 4,
    RangeE() => 4,
    Ternary() || Assign() || FuncE() => -1,
    _ => 50,
  };
}

/// `left op right` with parentheses where the operands need them.
String buildOp(String op, String left, String right) {
  final level = opLevels[op] ?? 4;
  String wrap(String x, bool right) {
    final p = _precedence(x);
    final need = right ? p <= level : p < level;
    return need ? '($x)' : x;
  }

  return '${wrap(left, false)} $op ${wrap(right, true)}';
}

String buildNot(String operand) =>
    _precedence(operand) >= 50 ? '!$operand' : '!($operand)';

String buildCall(String name, List<String> args, Map<String, String> named) =>
    callText(name, args, named);

/// A string literal for [value].
String quote(String value) {
  final b = StringBuffer('"');
  for (final ch in value.split('')) {
    b.write(switch (ch) {
      '\\' => r'\\',
      '"' => r'\"',
      '\n' => r'\n',
      '\t' => r'\t',
      '\r' => r'\r',
      _ => ch,
    });
  }
  b.write('"');
  return b.toString();
}
