// Parser of ClickScript: tokens -> syntax tree (optionally with source ranges).

import 'ast.dart';
import 'lexer.dart';
import 'values.dart';

List<Stmt> parseProgram(String source, {String? script}) {
  try {
    return Parser(Lexer(source).scan()).program();
  } on ScriptError catch (e) {
    e.script ??= script;
    rethrow;
  }
}

class Parser {
  final List<Token> t;
  int p = 0;

  /// When set, the token range [start, end) of every statement and
  /// expression is stored here (used by the block editor).
  final Map<Node, (int, int)>? spans;
  Parser(this.t, {this.spans});

  N _span<N extends Node>(int start, N node) {
    spans?[node] = (start, p);
    return node;
  }

  Token get cur => t[p];
  Token get next => t[p + 1 < t.length ? p + 1 : p];
  Token _adv() => t[p < t.length - 1 ? p++ : p];

  Never _err(String m, [Token? at]) => throw ScriptError(m, (at ?? cur).line);

  bool _op(String s) {
    if (cur.isOp(s)) {
      p++;
      return true;
    }
    return false;
  }

  bool _kw(String s) {
    if (cur.isKw(s)) {
      p++;
      return true;
    }
    return false;
  }

  void _need(String s) {
    if (!_op(s)) _err("Ожидалось '$s', а встретилось $cur");
  }

  String _identName() {
    if (cur.type != T.ident) _err('Ожидалось имя, а встретилось $cur');
    return _adv().text;
  }

  List<Stmt> program() {
    final out = <Stmt>[];
    while (cur.type != T.eof) {
      out.add(statement());
    }
    return out;
  }

  Block block() {
    final start = p;
    final ln = cur.line;
    _need('{');
    final out = <Stmt>[];
    while (!cur.isOp('}')) {
      if (cur.type == T.eof) _err("Не закрыта фигурная скобка '{'", t[p - 1]);
      out.add(statement());
    }
    p++;
    return _span(start, Block(out, ln));
  }

  Stmt statement() {
    final start = p;
    return _span(start, _statement());
  }

  Stmt _statement() {
    final c = cur;
    final ln = c.line;
    if (c.type == T.op) {
      if (c.text == '{') return block();
      if (c.text == ';') {
        p++;
        return Block(const [], ln);
      }
    }
    if (c.type == T.keyword) {
      switch (c.text) {
        case 'let' || 'var' || 'const':
          final s = _varDecl();
          _op(';');
          return s;
        case 'if':
          p++;
          _need('(');
          final cond = expression();
          _need(')');
          final then = statement();
          Stmt? other;
          if (_kw('else')) other = statement();
          return If(cond, then, other, ln);
        case 'while':
          p++;
          _need('(');
          final cond = expression();
          _need(')');
          return While(cond, statement(), false, ln);
        case 'do':
          p++;
          final body = statement();
          if (!_kw('while')) _err("После do { } ожидалось 'while'");
          _need('(');
          final cond = expression();
          _need(')');
          _op(';');
          return While(cond, body, true, ln);
        case 'for':
          return _for();
        case 'repeat':
          p++;
          Expr? count;
          if (_op('(')) {
            count = expression();
            _need(')');
          }
          return Repeat(count, statement(), ln);
        case 'break':
          p++;
          _op(';');
          return Break(ln);
        case 'continue':
          p++;
          _op(';');
          return Continue(ln);
        case 'return':
          p++;
          Expr? v;
          if (!cur.isOp(';') && !cur.isOp('}') && cur.type != T.eof && !cur.nl) {
            v = expression();
          }
          _op(';');
          return Return(v, ln);
        case 'async':
          if (next.isKw('function')) {
            p++;
            return statement();
          }
        case 'function':
          if (next.type == T.ident) {
            p++;
            final name = _adv().text;
            return FuncDecl(_funcRest(name, ln), ln);
          }
        case 'switch':
          return _switch();
        case 'try':
          p++;
          final body = block();
          String? errName;
          Block? handler;
          Block? fin;
          if (_kw('catch')) {
            if (_op('(')) {
              errName = _identName();
              _need(')');
            }
            handler = block();
          }
          if (_kw('finally')) fin = block();
          if (handler == null && fin == null) {
            _err("После try { } нужен catch или finally");
          }
          return Try(body, errName, handler, fin, ln);
        case 'throw':
          p++;
          final v = expression();
          _op(';');
          return Throw(v, ln);
      }
    }
    final e = expression();
    if (e is Call && cur.isOp('{')) {
      final callee = e.callee;
      if (callee is Ident && scopedCalls.contains(callee.name)) {
        return WithS(e, block(), ln);
      }
    }
    _op(';');
    return ExprS(e, ln);
  }

  VarS _varDecl() {
    final ln = cur.line;
    p++; // let / var / const
    final decls = <MapEntry<String, Expr?>>[];
    do {
      final name = _identName();
      Expr? init;
      if (_op('=')) init = assignment();
      decls.add(MapEntry(name, init));
    } while (_op(','));
    return VarS(decls, ln);
  }

  Stmt _for() {
    final ln = cur.line;
    p++;
    _need('(');
    // for (let x in/of expr)  |  for (x in expr)
    final save = p;
    if (cur.isKw('let') || cur.isKw('var') || cur.isKw('const')) p++;
    if (cur.type == T.ident && (next.isKw('in') || next.isKw('of'))) {
      final name = _adv().text;
      p++;
      final it = expression();
      _need(')');
      return ForIn(name, it, statement(), ln);
    }
    p = save;
    Stmt? init;
    if (!cur.isOp(';')) {
      if (cur.isKw('let') || cur.isKw('var') || cur.isKw('const')) {
        init = _varDecl();
      } else {
        init = ExprS(expression(), ln);
      }
    }
    _need(';');
    Expr? cond;
    if (!cur.isOp(';')) cond = expression();
    _need(';');
    Expr? step;
    if (!cur.isOp(')')) step = expression();
    _need(')');
    return ForC(init, cond, step, statement(), ln);
  }

  Stmt _switch() {
    final ln = cur.line;
    p++;
    _need('(');
    final subject = expression();
    _need(')');
    _need('{');
    final cases = <SwitchCase>[];
    while (!cur.isOp('}')) {
      Expr? test;
      if (_kw('case')) {
        test = expression();
      } else if (!_kw('default')) {
        _err("Внутри switch ожидалось 'case' или 'default'");
      }
      _need(':');
      final body = <Stmt>[];
      while (!cur.isKw('case') && !cur.isKw('default') && !cur.isOp('}')) {
        if (cur.type == T.eof) _err('switch не закрыт');
        body.add(statement());
      }
      cases.add(SwitchCase(test, body));
    }
    p++;
    return Switch(subject, cases, ln);
  }

  FuncE _funcRest(String? name, int ln) {
    _need('(');
    final params = <String>[];
    while (!cur.isOp(')')) {
      params.add(_identName());
      if (_op('=')) {
        _err('Значения параметров по умолчанию не поддерживаются');
      }
      if (!_op(',')) break;
    }
    _need(')');
    return FuncE(name, params, block(), null, ln);
  }

  // -------------------------------------------------------------- expressions

  Expr expression() => assignment();

  Expr assignment() {
    final start = p;
    return _span(start, _assignment());
  }

  Expr _assignment() {
    final left = _ternary();
    final c = cur;
    if (c.type == T.op &&
        const {'=', '+=', '-=', '*=', '/=', '%='}.contains(c.text)) {
      if (left is! Ident && left is! Member && left is! Index) {
        _err('Слева от ${c.text} должна быть переменная');
      }
      p++;
      return Assign(left, c.text, assignment(), c.line);
    }
    return left;
  }

  Expr _ternary() {
    final start = p;
    final c = _binary(0);
    if (cur.isOp('?')) {
      final ln = cur.line;
      p++;
      final a = assignment();
      _need(':');
      final b = assignment();
      return _span(start, Ternary(c, a, b, ln));
    }
    return c;
  }

  static const _levels = <Set<String>>[
    {'||', '??'},
    {'&&'},
    {'==', '!=', '===', '!=='},
    {'<', '<=', '>', '>='},
    {'..'},
    {'+', '-'},
    {'*', '/', '%'},
  ];

  Expr _binary(int level) {
    if (level >= _levels.length) return _unary();
    final start = p;
    var left = _binary(level + 1);
    while (cur.type == T.op && _levels[level].contains(cur.text)) {
      final op = _adv();
      final right = _binary(level + 1);
      if (level <= 1) {
        left = Logical(op.text, left, right, op.line);
      } else if (op.text == '..') {
        left = RangeE(left, right, op.line);
      } else {
        left = Binary(op.text, left, right, op.line);
      }
      _span(start, left);
    }
    return left;
  }

  Expr _unary() {
    final c = cur;
    final start = p;
    if (c.type == T.op) {
      if (c.text == '!' || c.text == '-' || c.text == '+') {
        p++;
        return _span(start, Unary(c.text, _unary(), c.line));
      }
      if (c.text == '++' || c.text == '--') {
        p++;
        return _span(start, Update(_unary(), c.text, true, c.line));
      }
    }
    if (c.isKw('await')) {
      p++;
      return _unary();
    }
    return _postfix();
  }

  Expr _postfix() {
    final start = p;
    var e = _span(start, _primary());
    while (true) {
      final c = cur;
      if (c.type != T.op) break;
      if (c.text == '(' && !c.nl) {
        p++;
        final args = <Expr>[];
        final named = <String, Expr>{};
        while (!cur.isOp(')')) {
          if ((cur.type == T.ident || cur.type == T.keyword) &&
              next.isOp(':')) {
            final name = _adv().text;
            p++;
            named[name] = assignment();
          } else {
            args.add(assignment());
          }
          if (!_op(',')) break;
        }
        _need(')');
        e = Call(e, args, named, c.line);
      } else if (c.text == '.') {
        p++;
        if (cur.type != T.ident && cur.type != T.keyword) {
          _err('После точки ожидалось имя');
        }
        e = Member(e, _adv().text, c.line);
      } else if (c.text == '[' && !c.nl) {
        p++;
        final idx = expression();
        _need(']');
        e = Index(e, idx, c.line);
      } else if ((c.text == '++' || c.text == '--') && !c.nl) {
        p++;
        e = Update(e, c.text, false, c.line);
      } else {
        break;
      }
      _span(start, e);
    }
    return e;
  }

  bool _arrowAhead() {
    // cur is '('; find the matching ')' and check for '=>'.
    var depth = 0;
    for (var j = p; j < t.length; j++) {
      final x = t[j];
      if (x.type != T.op) continue;
      if (x.text == '(') depth++;
      if (x.text == ')') {
        depth--;
        if (depth == 0) return j + 1 < t.length && t[j + 1].isOp('=>');
      }
    }
    return false;
  }

  FuncE _arrowRest(List<String> params, int ln) {
    _need('=>');
    if (cur.isOp('{')) return FuncE(null, params, block(), null, ln);
    return FuncE(null, params, null, assignment(), ln);
  }

  Expr _primary() {
    final c = cur;
    final ln = c.line;
    switch (c.type) {
      case T.number || T.percent || T.string:
        p++;
        return Lit(c.value, ln);
      case T.template:
        p++;
        final parts = <Object>[];
        for (final part in c.value as List<Object>) {
          if (part is TemplateExpr) {
            final sub = Parser(Lexer(part.source, startLine: part.line).scan());
            parts.add(sub.expression());
            if (sub.cur.type != T.eof) {
              throw ScriptError(r'Лишний текст внутри ${ }', part.line);
            }
          } else {
            parts.add(part);
          }
        }
        return TemplateE(parts, ln);
      case T.ident:
        if (next.isOp('=>')) {
          p++;
          return _arrowRest([c.text], ln);
        }
        p++;
        return Ident(c.text, ln);
      case T.keyword:
        switch (c.text) {
          case 'true':
            p++;
            return Lit(true, ln);
          case 'false':
            p++;
            return Lit(false, ln);
          case 'null' || 'undefined':
            p++;
            return Lit(null, ln);
          case 'async':
            p++;
            return _primary();
          case 'function':
            p++;
            String? name;
            if (cur.type == T.ident) name = _adv().text;
            return _funcRest(name, ln);
        }
        _err("Слово '${c.text}' здесь не к месту");
      case T.op:
        if (c.text == '(') {
          if (_arrowAhead()) {
            p++;
            final params = <String>[];
            while (!cur.isOp(')')) {
              params.add(_identName());
              if (!_op(',')) break;
            }
            _need(')');
            return _arrowRest(params, ln);
          }
          final open = p;
          p++;
          final e = expression();
          _need(')');
          return _span(open, e);
        }
        if (c.text == '[') {
          p++;
          final items = <Expr>[];
          while (!cur.isOp(']')) {
            items.add(assignment());
            if (!_op(',')) break;
          }
          _need(']');
          return ArrayE(items, ln);
        }
        if (c.text == '{') {
          p++;
          final entries = <MapEntry<String, Expr>>[];
          while (!cur.isOp('}')) {
            final k = cur;
            String key;
            if (k.type == T.ident || k.type == T.keyword) {
              key = k.text;
            } else if (k.type == T.string) {
              key = k.value as String;
            } else if (k.type == T.number) {
              key = fmtNum(k.value as num);
            } else {
              _err('Ожидался ключ объекта');
            }
            p++;
            if (_op(':')) {
              entries.add(MapEntry(key, assignment()));
            } else {
              entries.add(MapEntry(key, Ident(key, k.line)));
            }
            if (!_op(',')) break;
          }
          _need('}');
          return MapE(entries, ln);
        }
        _err('Неожиданный символ $c');
      case T.eof:
        _err('Неожиданный конец скрипта');
    }
  }
}
