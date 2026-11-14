// Checks the block editor on real scripts: every .cks file in a folder
// (default: %APPDATA%\SmartClicker\scripts) must turn into blocks and back
// without changes, and code generated anew from the blocks must parse to
// the same program. Nothing is written.
//
//   dart run tool/smoke_blocks.dart [folder]
import 'dart:io';

import 'package:smart_clicker/core/blocks/blocks.dart';
import 'package:smart_clicker/core/lang/ast.dart';
import 'package:smart_clicker/core/lang/parser.dart';

void main(List<String> args) {
  final dir = Directory(args.isNotEmpty
      ? args.first
      : '${Platform.environment['APPDATA']}\\SmartClicker\\scripts');
  var ok = 0, bad = 0, code = 0, blocks = 0;
  for (final f in dir.listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.cks')) continue;
    final name = f.path.substring(dir.path.length + 1);
    final src = f.readAsStringSync();
    try {
      final doc = parseBlocks(src);
      final all = doc.all.toList();
      blocks += all.length;
      code += all.where((n) => n.kind == BK.code).length;
      if (doc.code() != src) throw 'код изменился без правок';
      for (final n in all) {
        n.src = null;
      }
      final again = doc.code();
      if (_dump(again) != _dump(src)) throw 'заново собранный код делает другое:\n$again';
      ok++;
      stdout.writeln('ok   $name: ${all.length} блоков');
    } on Object catch (e) {
      bad++;
      stdout.writeln('FAIL $name: $e');
    }
  }
  stdout.writeln('\nскриптов: ${ok + bad}, ошибок: $bad; блоков: $blocks, из них «код как есть»: $code');
  if (bad > 0) exitCode = 1;
}

String _dump(String code) => parseProgram(code).map(_d).join('\n');

String _d(Object? n) => switch (n) {
      null => '_',
      Lit(value: final v) => 'lit(${v.runtimeType}:$v)',
      TemplateE(parts: final p) => 'tpl(${p.map((x) => x is String ? x : _d(x)).join('|')})',
      Ident(name: final s) => s,
      ArrayE(items: final i) => '[${i.map(_d).join(',')}]',
      MapE(entries: final e) => '{${e.map((x) => '${x.key}:${_d(x.value)}').join(',')}}',
      Unary(op: final o, e: final e) => '($o${_d(e)})',
      Binary(op: final o, l: final l, r: final r) ||
      Logical(op: final o, l: final l, r: final r) =>
        '(${_d(l)}$o${_d(r)})',
      Ternary(c: final c, a: final a, b: final b) => '(${_d(c)}?${_d(a)}:${_d(b)})',
      Assign(target: final t, op: final o, value: final v) => '${_d(t)}$o${_d(v)}',
      Update(target: final t, op: final o) => '${_d(t)}$o',
      Call(callee: final c, args: final a, named: final n) =>
        '${_d(c)}(${a.map(_d).join(',')};${n.entries.map((e) => '${e.key}=${_d(e.value)}').join(',')})',
      Member(obj: final o, name: final s) => '${_d(o)}.$s',
      Index(obj: final o, idx: final i) => '${_d(o)}[${_d(i)}]',
      RangeE(lo: final l, hi: final h) => '${_d(l)}..${_d(h)}',
      FuncE(name: final s, params: final p, body: final b, exprBody: final e) =>
        'fn $s(${p.join(',')}){${_d(b)}${_d(e)}}',
      ExprS(e: final e) => _d(e),
      VarS(decls: final d) => 'let ${d.map((x) => '${x.key}=${_d(x.value)}').join(',')}',
      Block(body: final b) => '{${b.map(_d).join(';')}}',
      If(cond: final c, then: final t, otherwise: final o) => 'if(${_d(c)})${_b(t)}else${_b(o)}',
      While(cond: final c, body: final b, doWhile: final d) => 'while$d(${_d(c)})${_b(b)}',
      ForC(init: final i, cond: final c, step: final s, body: final b) =>
        'for(${_d(i)};${_d(c)};${_d(s)})${_b(b)}',
      ForIn(name: final s, iterable: final i, body: final b) => 'for($s in ${_d(i)})${_b(b)}',
      Repeat(count: final c, body: final b) => 'repeat(${_d(c)})${_b(b)}',
      Break() => 'break',
      Continue() => 'continue',
      Return(value: final v) => 'return ${_d(v)}',
      FuncDecl(fn: final f) => _d(f),
      Switch(subject: final s, cases: final c) =>
        'switch(${_d(s)}){${c.map((x) => '${_d(x.test)}:${x.body.map(_d).join(';')}').join('|')}}',
      Try(body: final b, errName: final e, handler: final h, finalizer: final f) =>
        'try${_d(b)}catch($e)${_d(h)}finally${_d(f)}',
      Throw(value: final v) => 'throw ${_d(v)}',
      _ => '?$n',
    };

String _b(Stmt? s) => s == null ? '_' : (s is Block ? _d(s) : '{${_d(s)}}');
