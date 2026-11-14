// Lexer of ClickScript: text -> tokens (with offsets and comments for blocks).

import 'values.dart';

enum T { number, percent, string, template, ident, keyword, op, eof }

class Token {
  final T type;
  final String text;
  final Object? value;
  final int line;

  /// True when at least one line break precedes this token.
  final bool nl;

  /// Offsets of the token in the source: [start, end).
  final int start;
  final int end;
  const Token(this.type, this.text, this.value, this.line, this.nl,
      [this.start = 0, this.end = 0]);

  bool isOp(String s) => type == T.op && text == s;
  bool isKw(String s) => type == T.keyword && text == s;
  @override
  String toString() => type == T.eof ? 'конец файла' : "'$text'";
}

/// A `// ...` or `/* ... */` comment; kept by the lexer for the block
/// editor (the interpreter ignores them).
class Comment {
  /// Offsets in the source: [start, end), including `//` or `/* */`.
  final int start;
  final int end;
  final int line;
  final bool block;
  const Comment(this.start, this.end, this.line, this.block);
}

/// An embedded `${...}` expression inside a template string.
class TemplateExpr {
  final String source;
  final int line;
  const TemplateExpr(this.source, this.line);
}

const keywords = {
  'let', 'var', 'const', 'if', 'else', 'while', 'for', 'in', 'of', 'repeat',
  'break', 'continue', 'return', 'function', 'true', 'false', 'null',
  'undefined', 'switch', 'case', 'default', 'try', 'catch', 'finally',
  'throw', 'await', 'async', 'do', //
};

const _ops = [
  '===', '!==', '...', '==', '!=', '<=', '>=', '&&', '||', '??', '+=', '-=',
  '*=', '/=', '%=', '++', '--', '..', '=>', '+', '-', '*', '/', '%', '<', '>',
  '=', '!', '(', ')', '{', '}', '[', ']', ',', ';', ':', '.', '?', //
];

const _units = <String, num>{
  'ms': 1,
  's': 1000,
  'sec': 1000,
  'm': 60000,
  'min': 60000,
  'h': 3600000,
  'px': 1,
};

class Lexer {
  final String s;
  int i = 0;
  int line = 1;
  bool _nl = false;
  int _tokStart = 0;
  final List<Token> out = [];

  /// All comments of the source, in order.
  final List<Comment> comments = [];

  Lexer(this.s, {int startLine = 1}) {
    line = startLine;
  }

  Never _err(String m) => throw ScriptError(m, line);

  bool _isDigit(String c) => c.compareTo('0') >= 0 && c.compareTo('9') <= 0;
  bool _isIdStart(String c) => RegExp(r'[A-Za-z_$Ѐ-ӿ]').hasMatch(c);
  bool _isIdPart(String c) => _isIdStart(c) || _isDigit(c);

  void _add(T t, String text, [Object? value, int? atLine]) {
    out.add(Token(t, text, value, atLine ?? line, _nl, _tokStart, i));
    _nl = false;
  }

  List<Token> scan() {
    while (true) {
      _skipSpace();
      _tokStart = i;
      if (i >= s.length) break;
      final c = s[i];
      if (_isDigit(c) ||
          (c == '.' && i + 1 < s.length && _isDigit(s[i + 1]))) {
        _number();
      } else if (_isIdStart(c)) {
        final st = i;
        while (i < s.length && _isIdPart(s[i])) {
          i++;
        }
        final w = s.substring(st, i);
        _add(keywords.contains(w) ? T.keyword : T.ident, w);
      } else if (c == '"' || c == "'") {
        final ln = line;
        _add(T.string, c, _string(c), ln);
      } else if (c == '`') {
        final ln = line;
        i++;
        _add(T.template, '`', _template(), ln);
      } else if (c == '#' && _hexColorAhead()) {
        // Bare colour literal: #FF0000
        final st = i;
        i++;
        while (i < s.length && RegExp(r'[0-9A-Fa-f]').hasMatch(s[i])) {
          i++;
        }
        _add(T.string, s.substring(st, i), s.substring(st, i).toUpperCase());
      } else {
        final op = _ops.firstWhere((o) => s.startsWith(o, i),
            orElse: () => _err("Неожиданный символ '$c'"));
        i += op.length;
        _add(T.op, op);
      }
    }
    _add(T.eof, '');
    return out;
  }

  bool _hexColorAhead() {
    final m = RegExp(r'#[0-9A-Fa-f]+').matchAsPrefix(s, i);
    if (m == null) return false;
    final n = m.end - m.start - 1;
    return n == 6 || n == 3;
  }

  void _skipSpace() {
    while (i < s.length) {
      final c = s[i];
      if (c == '\n') {
        line++;
        _nl = true;
        i++;
      } else if (c == ' ' || c == '\t' || c == '\r' || c == '﻿') {
        i++;
      } else if (s.startsWith('//', i)) {
        final st = i;
        while (i < s.length && s[i] != '\n') {
          i++;
        }
        comments.add(Comment(st, i, line, false));
      } else if (s.startsWith('/*', i)) {
        final end = s.indexOf('*/', i + 2);
        if (end < 0) _err('Комментарий /* не закрыт');
        comments.add(Comment(i, end + 2, line, true));
        line += '\n'.allMatches(s.substring(i, end)).length;
        i = end + 2;
      } else {
        break;
      }
    }
  }

  void _number() {
    final st = i;
    num value;
    if (s.startsWith('0x', i) || s.startsWith('0X', i)) {
      i += 2;
      while (i < s.length && RegExp(r'[0-9A-Fa-f]').hasMatch(s[i])) {
        i++;
      }
      value = int.parse(s.substring(st + 2, i), radix: 16);
    } else {
      var isDouble = false;
      while (i < s.length && _isDigit(s[i])) {
        i++;
      }
      if (i + 1 < s.length && s[i] == '.' && _isDigit(s[i + 1])) {
        isDouble = true;
        i++;
        while (i < s.length && _isDigit(s[i])) {
          i++;
        }
      }
      final txt = s.substring(st, i);
      value = isDouble ? double.parse(txt) : int.parse(txt);
    }
    if (i < s.length && _isIdStart(s[i])) {
      final us = i;
      while (i < s.length && _isIdPart(s[i])) {
        i++;
      }
      final unit = s.substring(us, i);
      final mul = _units[unit];
      if (mul == null) {
        _err("Неизвестная единица '$unit' после числа (можно: ms, s, m, h, px)");
      }
      value = value * mul;
    }
    if (i < s.length && s[i] == '%' && _percentAhead()) {
      i++;
      _add(T.percent, s.substring(st, i), Percent(value.toDouble()));
      return;
    }
    _add(T.number, s.substring(st, i), value);
  }

  /// `50%` is a percent literal unless an operand follows (`10%3`).
  bool _percentAhead() {
    var j = i + 1;
    while (j < s.length && (s[j] == ' ' || s[j] == '\t')) {
      j++;
    }
    if (j >= s.length) return true;
    final c = s[j];
    if (c == '=') return false; // 10 %= ...
    return !(_isDigit(c) || _isIdStart(c) || c == '(' || c == '"' || c == "'");
  }

  String _escape() {
    // s[i] == '\\'
    i++;
    if (i >= s.length) _err('Строка не закрыта');
    final c = s[i++];
    switch (c) {
      case 'n':
        return '\n';
      case 't':
        return '\t';
      case 'r':
        return '\r';
      case '0':
        return '\x00';
      case 'u':
        if (i + 4 <= s.length) {
          final code = int.tryParse(s.substring(i, i + 4), radix: 16);
          if (code != null) {
            i += 4;
            return String.fromCharCode(code);
          }
        }
        return 'u';
      default:
        return c;
    }
  }

  String _string(String q) {
    i++;
    final sb = StringBuffer();
    while (true) {
      if (i >= s.length || s[i] == '\n') _err('Строка не закрыта кавычкой $q');
      final c = s[i];
      if (c == q) {
        i++;
        break;
      }
      if (c == '\\') {
        sb.write(_escape());
        continue;
      }
      sb.write(c);
      i++;
    }
    return sb.toString();
  }

  List<Object> _template() {
    final parts = <Object>[];
    final sb = StringBuffer();
    while (true) {
      if (i >= s.length) _err('Шаблонная строка не закрыта символом `');
      final c = s[i];
      if (c == '`') {
        i++;
        break;
      }
      if (c == '\\') {
        sb.write(_escape());
        continue;
      }
      if (c == r'$' && i + 1 < s.length && s[i + 1] == '{') {
        if (sb.isNotEmpty) {
          parts.add(sb.toString());
          sb.clear();
        }
        i += 2;
        var depth = 1;
        final st = i;
        final ln = line;
        while (i < s.length && depth > 0) {
          if (s[i] == '{') depth++;
          if (s[i] == '}') depth--;
          if (s[i] == '\n') line++;
          i++;
        }
        if (depth > 0) _err(r'Не закрыта ${ в шаблонной строке');
        parts.add(TemplateExpr(s.substring(st, i - 1), ln));
        continue;
      }
      if (c == '\n') line++;
      sb.write(c);
      i++;
    }
    if (sb.isNotEmpty) parts.add(sb.toString());
    return parts;
  }
}
