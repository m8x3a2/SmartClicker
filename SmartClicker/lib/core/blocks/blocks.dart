// Model of the block constructor: code -> blocks (keeping comments and the
// original text) and blocks -> code; edits of the blocks.

import '../lang/ast.dart';
import '../lang/lexer.dart';
import '../lang/parser.dart';

/// Kinds of statement blocks.
abstract final class BK {
  static const call = 'call';
  static const let = 'let';
  static const set = 'set';
  static const ifs = 'if';
  static const repeat = 'repeat';
  static const whiles = 'while';
  static const doWhile = 'do';
  static const forIn = 'for';
  static const forC = 'forc';
  static const func = 'func';
  static const ret = 'return';
  static const brk = 'break';
  static const cont = 'continue';
  static const thr = 'throw';
  static const tryc = 'try';
  static const sw = 'switch';
  static const comment = 'comment';
  static const code = 'code';
  static const withWin = 'with';

  /// Kinds that hold other blocks.
  static const containers = {
    ifs, repeat, whiles, doWhile, forIn, forC, func, tryc, sw, withWin,
  };
}

/// One statement of the script shown as a block.
///
/// The code stays the only source of truth: blocks are parsed from it and
/// every change of a block writes the code back ([generate]). A block that
/// was not changed keeps its original text ([src]), so editing one block
/// does not reformat the rest of the script.
class BNode {
  final String kind;

  /// call: function name · let/for: variable · set: target · func: name ·
  /// try: error variable · comment: text after `//` (lines) · code: source.
  String text;

  /// let: `let`/`var`/`const` · set: operator · func: parameters ·
  /// forc: the header inside `for ( )` · try: `c`/`f`/`cf` (catch, finally) ·
  /// comment: `block` for `/* */`.
  String extra;

  /// Expressions as source text: call arguments; conditions of `if`
  /// branches; count of `repeat`; value of `let`/`set`/`return`/`throw`;
  /// iterable of `for`; subject and case tests of `switch` ('' = default).
  final List<String> args;

  /// Named arguments of a call (`button: "right"`).
  final Map<String, String> named;

  /// Nested blocks: `if` branches (+ else), loop body, `try`/`catch`/
  /// `finally`, `switch` cases.
  final List<List<BNode>> bodies;

  /// Empty lines before the block.
  int blank = 0;

  /// A comment on the same line after the statement (`// ...` with the
  /// slashes) and the spaces before it.
  String? tail;
  int tailGap = 2;

  /// A `/* */` comment before the statement on the same line, with the
  /// spaces after it.
  String? lead;

  /// The statement ended with `;`.
  bool semi = false;

  /// Original text (without the leading indent) while the block is unchanged.
  String? src;

  /// [src] has multi-line strings: its lines are not re-indented.
  bool verbatim = false;

  /// Lines of the statement in the code the blocks were parsed from.
  int line = 0;
  int endLine = 0;

  BNode? parent;

  BNode(this.kind,
      {this.text = '',
      this.extra = '',
      List<String>? args,
      Map<String, String>? named,
      List<List<BNode>>? bodies})
      : args = args ?? [],
        named = named ?? {},
        bodies = bodies ?? [];

  bool get isContainer => BK.containers.contains(kind);

  /// `if` has an `else` branch.
  bool get hasElse => kind == BK.ifs && bodies.length > args.length;

  /// Labels of [bodies] for the try block.
  bool get hasCatch => kind == BK.tryc && extra.contains('c');
  bool get hasFinally => kind == BK.tryc && extra.contains('f');

  /// The line range of the block contains [l].
  bool covers(int l) => l >= line && l <= endLine;

  /// Every block inside this one (depth first).
  Iterable<BNode> get descendants sync* {
    for (final b in bodies) {
      for (final n in b) {
        yield n;
        yield* n.descendants;
      }
    }
  }

  @override
  String toString() => 'BNode($kind ${text.isEmpty ? '' : text})';
}

/// Blocks of a whole script.
class BlockDoc {
  final List<BNode> nodes;

  /// One level of indentation as used in the script.
  String unit;
  bool finalNewline;
  int endBlank;

  BlockDoc(this.nodes, {this.unit = '    ', this.finalNewline = true, this.endBlank = 0}) {
    relink();
  }

  /// All blocks, depth first.
  Iterable<BNode> get all sync* {
    for (final n in nodes) {
      yield n;
      yield* n.descendants;
    }
  }

  void relink() {
    void walk(List<BNode> list, BNode? parent) {
      for (final n in list) {
        n.parent = parent;
        for (final b in n.bodies) {
          walk(b, n);
        }
      }
    }

    walk(nodes, null);
  }

  /// The list that holds [n].
  List<BNode> listOf(BNode n) {
    final p = n.parent;
    if (p == null) return nodes;
    return p.bodies.firstWhere((b) => b.contains(n));
  }

  List<BNode> body(BNode? owner, int body) =>
      owner == null ? nodes : owner.bodies[body];

  /// Forgets the original text of [n] and its parents: they are generated.
  static void touch(BNode? n) {
    for (var x = n; x != null; x = x.parent) {
      x.src = null;
    }
  }

  /// Address of [n]: index in the script, then body and index for every
  /// level inside. Survives parsing the generated code again.
  List<int> pathOf(BNode n) {
    final out = <int>[];
    for (BNode? x = n; x != null; x = x.parent) {
      final p = x.parent;
      if (p == null) {
        out.insert(0, nodes.indexOf(x));
      } else {
        final b = p.bodies.indexWhere((l) => l.contains(x));
        out.insertAll(0, [b, p.bodies[b].indexOf(x)]);
      }
    }
    return out;
  }

  BNode? resolve(List<int> path) {
    if (path.isEmpty || path[0] < 0 || path[0] >= nodes.length) return null;
    var n = nodes[path[0]];
    for (var i = 1; i + 1 < path.length; i += 2) {
      final b = path[i], j = path[i + 1];
      if (b >= n.bodies.length || j < 0 || j >= n.bodies[b].length) return null;
      n = n.bodies[b][j];
    }
    return n;
  }

  /// The innermost block whose lines contain [line].
  BNode? at(int line) {
    BNode? found;
    void walk(List<BNode> list) {
      for (final n in list) {
        if (n.kind == BK.comment || !n.covers(line)) continue;
        found = n;
        for (final b in n.bodies) {
          walk(b);
        }
        return;
      }
    }

    walk(nodes);
    return found;
  }

  void insert(BNode? owner, int body, int index, List<BNode> items) {
    final list = this.body(owner, body);
    list.insertAll(index.clamp(0, list.length), items);
    relink();
    touch(owner);
  }

  void remove(BNode n) {
    final p = n.parent;
    listOf(n).remove(n);
    relink();
    touch(p);
  }

  /// [n] is [other] or contains it.
  static bool contains(BNode n, BNode? other) {
    for (var x = other; x != null; x = x.parent) {
      if (identical(x, n)) return true;
    }
    return false;
  }

  /// Moves [n] to position [index] of a body of [owner]; false if the
  /// block would land inside itself.
  bool move(BNode n, BNode? owner, int body, int index) {
    if (contains(n, owner)) return false;
    final from = listOf(n);
    final to = this.body(owner, body);
    final old = from.indexOf(n);
    if (identical(from, to) && old < index) index--;
    touch(n.parent);
    from.removeAt(old);
    n.blank = 0;
    to.insert(index.clamp(0, to.length), n);
    relink();
    touch(owner);
    return true;
  }

  String code() => generate(this);
}

// ------------------------------------------------------------------- parsing

/// Parses a script into blocks. Throws [ScriptError] if the code has a
/// syntax error.
BlockDoc parseBlocks(String source) => _Builder(source).doc();

/// Blocks of a piece of code (palette items, pasted code). The first block
/// gets no empty line before it.
List<BNode> parseSnippet(String code) {
  final nodes = parseBlocks(code).nodes;
  if (nodes.isNotEmpty) nodes.first.blank = 0;
  for (final n in nodes) {
    n.parent = null;
  }
  return nodes;
}

class _Builder {
  final String s;
  late final List<Token> t;
  late final List<Comment> comments;
  final Map<Node, (int, int)> spans = Map.identity();
  final Set<int> claimed = {};

  _Builder(this.s);

  BlockDoc doc() {
    final lexer = Lexer(s);
    t = lexer.scan();
    comments = lexer.comments;
    final program = Parser(t, spans: spans).program();
    final nodes = _list(program, 0, s.length, top: true);
    var lastEnd = 0;
    if (nodes.isNotEmpty) lastEnd = _lastEnd;
    final rest = s.substring(lastEnd);
    final k = '\n'.allMatches(rest).length;
    return BlockDoc(nodes,
        unit: _indentUnit(), finalNewline: k > 0 || nodes.isEmpty, endBlank: k > 1 ? k - 1 : 0);
  }

  /// End offset of the last item handled by the top-level [_list].
  int _lastEnd = 0;

  String _indentUnit() {
    int? best;
    for (final line in s.split('\n')) {
      if (line.trim().isEmpty) continue;
      if (line.startsWith('\t')) return '\t';
      final n = line.length - line.trimLeft().length;
      if (n > 0 && (best == null || n < best)) best = n;
    }
    return best == null || best > 8 ? '    ' : ' ' * best;
  }

  int _start(Node n) => t[spans[n]!.$1].start;
  int _end(Node n) => t[spans[n]!.$2 - 1].end;

  int _column(int offset) {
    if (offset == 0) return 0;
    final ls = s.lastIndexOf('\n', offset - 1) + 1;
    return offset - ls;
  }

  /// Source of an expression; comments inside it are kept by the text.
  String _expr(Expr e) {
    final a = _start(e), b = _end(e);
    _claim(a, b);
    return s.substring(a, b);
  }

  void _claim(int a, int b) {
    for (var i = 0; i < comments.length; i++) {
      final c = comments[i];
      if (c.start >= a && c.end <= b) claimed.add(i);
    }
  }

  String _commentText(Comment c) =>
      s.substring(c.start, c.end).replaceAll('\r', '');

  /// Blocks of [stmts] that lie in the source range [from, to); comments
  /// of the range become comment blocks or tails of statements.
  List<BNode> _list(List<Stmt> stmts, int from, int to, {bool top = false}) {
    final items = <(int, int, Object)>[];
    for (final st in stmts) {
      final (a, b) = spans[st]!;
      if (st is Block && st.body.isEmpty && b - a == 1 && t[a].isOp(';')) continue;
      items.add((t[a].start, t[b - 1].end, st));
    }
    bool inside(Comment c) => items.any((i) => c.start >= i.$1 && c.end <= i.$2);
    for (var i = 0; i < comments.length; i++) {
      final c = comments[i];
      if (c.start < from || c.end > to || claimed.contains(i)) continue;
      if (inside(c)) continue;
      items.add((c.start, c.end, i));
    }
    items.sort((x, y) => x.$1.compareTo(y.$1));

    final out = <BNode>[];
    var prevEnd = from;
    BNode? prev;
    var prevLineComment = false;
    // Column of the tail comment handled last (-1: the last item was not one).
    var tailCol = -1;
    for (final (start, end, what) in items) {
      final gap = s.substring(prevEnd, start);
      final nl = '\n'.allMatches(gap).length;
      if (what is int) {
        final c = comments[what];
        claimed.add(what);
        final text = _commentText(c);
        if (prev != null && nl == 0 && !text.contains('\n')) {
          prev.tail = text;
          prev.tailGap = gap.length;
          prevEnd = end;
          prevLineComment = false;
          tailCol = _column(c.start);
          continue;
        }
        // A comment lined up under the tail comment of the line above
        // continues it.
        if (prev != null && tailCol >= 0 && nl == 1 && !c.block && _column(c.start) == tailCol) {
          prev.tail = '${prev.tail}${gap.replaceAll('\r', '')}$text';
          prevEnd = end;
          continue;
        }
        tailCol = -1;
        if (prev != null && prevLineComment && !c.block && nl == 1) {
          prev.text += '\n${text.substring(2)}';
          prev.endLine = c.line;
          prevEnd = end;
          continue;
        }
        final node = c.block
            ? BNode(BK.comment, text: text.substring(2, text.length - 2), extra: 'block')
            : BNode(BK.comment, text: text.substring(2));
        node
          ..line = c.line
          ..endLine = c.line + '\n'.allMatches(text).length;
        node.blank = out.isEmpty && top ? nl : (nl > 0 ? nl - 1 : 0);
        out.add(node);
        prev = node;
        prevLineComment = !c.block;
        prevEnd = end;
        continue;
      }
      final node = _stmt(what as Stmt);
      node.blank = out.isEmpty && top ? nl : (nl > 0 ? nl - 1 : 0);
      if (nl == 0 && prev != null && identical(prev, out.lastOrNull) &&
          prev.kind == BK.comment && prev.extra == 'block' && !prev.text.contains('\n')) {
        // `/* note */ click()`: the comment stays in front of the statement.
        out.removeLast();
        node
          ..lead = '/*${prev.text}*/$gap'
          ..blank = prev.blank;
      }
      out.add(node);
      prev = node;
      prevLineComment = false;
      tailCol = -1;
      prevEnd = end;
    }
    if (top) _lastEnd = prevEnd;
    return out;
  }

  /// Blocks of the body of a statement (`{ ... }` or a single statement).
  List<BNode> _body(Stmt st) {
    if (st is Block) {
      final (a, b) = spans[st]!;
      if (t[a].isOp('{')) return _list(st.body, t[a].end, t[b - 1].start);
    }
    final n = _stmt(st);
    n.blank = 0;
    return [n];
  }

  BNode _stmt(Stmt st) {
    final (a, b) = spans[st]!;
    final start = t[a].start, end = t[b - 1].end;
    BNode node;
    switch (st) {
      case ExprS(e: final Call c) when c.callee is Ident:
        node = BNode(BK.call,
            text: (c.callee as Ident).name,
            args: [for (final x in c.args) _expr(x)],
            named: {for (final e in c.named.entries) e.key: _expr(e.value)});
      case ExprS(e: final Assign e):
        node = BNode(BK.set, text: _expr(e.target), extra: e.op, args: [_expr(e.value)]);
      case ExprS(e: final Update e):
        node = BNode(BK.set, text: _expr(e.target), extra: e.op);
      case VarS(decls: final d) when d.length == 1:
        node = BNode(BK.let,
            text: d.single.key,
            extra: t[a].text,
            args: [if (d.single.value != null) _expr(d.single.value!)]);
      case If():
        final conds = <String>[], bodies = <List<BNode>>[];
        Stmt? other = st;
        while (other is If) {
          conds.add(_expr(other.cond));
          bodies.add(_body(other.then));
          other = other.otherwise;
        }
        if (other != null) bodies.add(_body(other));
        node = BNode(BK.ifs, args: conds, bodies: bodies);
      case While(doWhile: false):
        node = BNode(BK.whiles, args: [_expr(st.cond)], bodies: [_body(st.body)]);
      case While(doWhile: true):
        final body = _body(st.body);
        node = BNode(BK.doWhile, args: [_expr(st.cond)], bodies: [body]);
      case Repeat():
        node = BNode(BK.repeat,
            args: [if (st.count != null) _expr(st.count!)], bodies: [_body(st.body)]);
      case WithS(call: Call(callee: Ident(:final name)) && final c):
        node = BNode(BK.withWin,
            text: name,
            args: [for (final x in c.args) _expr(x)],
            named: {for (final e in c.named.entries) e.key: _expr(e.value)},
            bodies: [_body(st.body)]);
      case ForIn():
        node = BNode(BK.forIn,
            text: st.name, args: [_expr(st.iterable)], bodies: [_body(st.body)]);
      case ForC():
        final bodyStart = spans[st.body]!.$1;
        final header = s.substring(t[a + 1].end, t[bodyStart - 1].start).trim();
        node = BNode(BK.forC, extra: header, bodies: [_body(st.body)]);
      case FuncDecl(fn: final fn) when fn.body != null && fn.name != null:
        node = BNode(BK.func,
            text: fn.name!, extra: fn.params.join(', '), bodies: [_body(fn.body!)]);
      case Return():
        node = BNode(BK.ret, args: [if (st.value != null) _expr(st.value!)]);
      case Break():
        node = BNode(BK.brk);
      case Continue():
        node = BNode(BK.cont);
      case Throw():
        node = BNode(BK.thr, args: [_expr(st.value)]);
      case Try():
        node = BNode(BK.tryc,
            text: st.errName ?? '',
            extra: '${st.handler != null ? 'c' : ''}${st.finalizer != null ? 'f' : ''}',
            bodies: [
              _body(st.body),
              if (st.handler != null) _body(st.handler!),
              if (st.finalizer != null) _body(st.finalizer!),
            ]);
      case Switch():
        node = BNode(BK.sw, args: [
          _expr(st.subject),
          for (final c in st.cases) c.test == null ? '' : _expr(c.test!),
        ], bodies: [
          for (final c in st.cases) [for (final x in c.body) _stmt(x)..blank = 0],
        ]);
      default:
        node = BNode(BK.code);
    }
    // A comment that no part of the block keeps (e.g. between `}` and
    // `else`) would be lost when the block is generated: keep the
    // statement as code instead.
    var lost = false;
    for (var i = 0; i < comments.length; i++) {
      final c = comments[i];
      if (c.start >= start && c.end <= end && !claimed.contains(i)) {
        lost = true;
        claimed.add(i);
      }
    }
    final text = _dedent(a, b);
    if (lost || node.kind == BK.code) {
      _claim(start, end);
      node = BNode(BK.code, text: text.$1)..verbatim = text.$2;
    }
    node
      ..src = text.$1
      ..verbatim = text.$2
      ..line = t[a].line
      ..endLine = t[b - 1].line
      ..semi = t[b - 1].isOp(';') && !node.isContainer;
    for (final body in node.bodies) {
      for (final c in body) {
        c.parent = node;
      }
    }
    return node;
  }

  /// The statement text with the indentation of its first line removed
  /// from the following lines; `true` if it has multi-line strings and
  /// must stay as is.
  (String, bool) _dedent(int a, int b) {
    final start = t[a].start, end = t[b - 1].end;
    final text = s.substring(start, end).replaceAll('\r', '');
    if (!text.contains('\n')) return (text, false);
    for (var i = a; i < b; i++) {
      final tok = t[i];
      if (tok.type == T.template && s.substring(tok.start, tok.end).contains('\n')) {
        return (text, true);
      }
    }
    final col = _column(start);
    final lines = text.split('\n');
    for (var i = 1; i < lines.length; i++) {
      var k = 0;
      final l = lines[i];
      while (k < col && k < l.length && (l[k] == ' ' || l[k] == '\t')) {
        k++;
      }
      lines[i] = l.substring(k);
    }
    return (lines.join('\n'), false);
  }
}

// ---------------------------------------------------------------- generation

/// Code of a whole script.
String generate(BlockDoc doc) {
  final lines = <String>[];
  _emitList(lines, doc.nodes, '', doc.unit, top: true);
  final code = lines.join('\n');
  if (doc.nodes.isEmpty) return '';
  return doc.finalNewline ? '$code\n${'\n' * doc.endBlank}' : code;
}

/// Code of some blocks (copy, drag), without indentation.
String generateNodes(List<BNode> nodes, {String unit = '    '}) {
  final lines = <String>[];
  _emitList(lines, nodes, '', unit);
  return lines.join('\n');
}

void _emitList(List<String> lines, List<BNode> nodes, String ind, String unit,
    {bool top = false}) {
  for (var i = 0; i < nodes.length; i++) {
    final n = nodes[i];
    final blank = (i == 0 && !top) ? 0 : n.blank;
    for (var k = 0; k < blank; k++) {
      lines.add('');
    }
    _emit(lines, n, ind, unit);
  }
}

String callText(String name, List<String> args, Map<String, String> named) {
  final parts = [
    ...args,
    for (final e in named.entries) '${e.key}: ${e.value}',
  ];
  return '$name(${parts.join(', ')})';
}

void _emit(List<String> lines, BNode n, String ind, String unit) {
  void add(String text) => lines.add(text.isEmpty ? '' : '$ind$text');
  void block(List<BNode> body) => _emitList(lines, body, ind + unit, unit);
  void multi(String text, bool verbatim) {
    final parts = text.split('\n');
    add(parts.first);
    for (final p in parts.skip(1)) {
      lines.add(verbatim || p.isEmpty ? p : '$ind$p');
    }
  }

  final semi = n.semi ? ';' : '';
  final first = lines.length;
  final src = n.src;
  if (src != null) {
    multi(src, n.verbatim);
  } else {
    switch (n.kind) {
      case BK.call:
        add('${callText(n.text, n.args, n.named)}$semi');
      case BK.let:
        add('${n.extra.isEmpty ? 'let' : n.extra} ${n.text}'
            '${n.args.isEmpty || n.args[0].isEmpty ? '' : ' = ${n.args[0]}'}$semi');
      case BK.set:
        if (n.extra == '++' || n.extra == '--') {
          add('${n.text}${n.extra}$semi');
        } else {
          add('${n.text} ${n.extra.isEmpty ? '=' : n.extra} ${n.args.isEmpty ? 'null' : n.args[0]}$semi');
        }
      case BK.ifs:
        for (var i = 0; i < n.args.length; i++) {
          add('${i == 0 ? 'if' : '} else if'} (${n.args[i]}) {');
          block(n.bodies[i]);
        }
        if (n.hasElse) {
          add('} else {');
          block(n.bodies.last);
        }
        add('}');
      case BK.repeat:
        add(n.args.isEmpty || n.args[0].isEmpty ? 'repeat {' : 'repeat (${n.args[0]}) {');
        block(n.bodies[0]);
        add('}');
      case BK.withWin:
        add('${callText(n.text.isEmpty ? 'with_window' : n.text, n.args, n.named)} {');
        block(n.bodies[0]);
        add('}');
      case BK.whiles:
        add('while (${n.args[0]}) {');
        block(n.bodies[0]);
        add('}');
      case BK.doWhile:
        add('do {');
        block(n.bodies[0]);
        add('} while (${n.args[0]})$semi');
      case BK.forIn:
        add('for (${n.text} in ${n.args[0]}) {');
        block(n.bodies[0]);
        add('}');
      case BK.forC:
        add('for (${n.extra}) {');
        block(n.bodies[0]);
        add('}');
      case BK.func:
        add('function ${n.text}(${n.extra}) {');
        block(n.bodies[0]);
        add('}');
      case BK.ret:
        add(n.args.isEmpty || n.args[0].isEmpty ? 'return$semi' : 'return ${n.args[0]}$semi');
      case BK.brk:
        add('break$semi');
      case BK.cont:
        add('continue$semi');
      case BK.thr:
        add('throw ${n.args[0]}$semi');
      case BK.tryc:
        add('try {');
        block(n.bodies[0]);
        var i = 1;
        if (n.hasCatch) {
          add(n.text.isEmpty ? '} catch {' : '} catch (${n.text}) {');
          block(n.bodies[i++]);
        }
        if (n.hasFinally) {
          add('} finally {');
          block(n.bodies[i]);
        }
        add('}');
      case BK.sw:
        add('switch (${n.args[0]}) {');
        for (var i = 0; i < n.bodies.length; i++) {
          final test = i + 1 < n.args.length ? n.args[i + 1] : '';
          lines.add('$ind$unit${test.isEmpty ? 'default:' : 'case $test:'}');
          _emitList(lines, n.bodies[i], '$ind$unit$unit', unit);
        }
        add('}');
      case BK.comment:
        if (n.extra == 'block') {
          multi('/*${n.text}*/', true);
        } else {
          for (final l in n.text.split('\n')) {
            add('//$l');
          }
        }
      default:
        multi(n.text, n.verbatim);
    }
  }
  if (n.lead != null && first < lines.length) {
    final l = lines[first];
    lines[first] = '$ind${n.lead}${l.length >= ind.length ? l.substring(ind.length) : l}';
  }
  if (n.tail != null && lines.isNotEmpty) {
    lines[lines.length - 1] += '${' ' * n.tailGap}${n.tail}';
  }
}
