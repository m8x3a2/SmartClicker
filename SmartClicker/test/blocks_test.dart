import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/core/lang/completions.dart';
import 'package:smart_clicker/core/storage/storage.dart';
import 'package:smart_clicker/app/templates/script_templates.dart';
import 'package:smart_clicker/core/blocks/blocks.dart';
import 'package:smart_clicker/core/blocks/catalog.dart';
import 'package:smart_clicker/core/blocks/expr.dart';
import 'package:smart_clicker/core/engine/runtime.dart';
import 'package:smart_clicker/core/lang/ast.dart';
import 'package:smart_clicker/core/lang/lexer.dart';
import 'package:smart_clicker/core/lang/parser.dart';
import 'package:smart_clicker/platform/stub_backend.dart';

/// The program as a string without line numbers: equal dumps — equal code.
String dump(String code) => parseProgram(code).map(_d).join('\n');

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
      If(cond: final c, then: final t, otherwise: final o) => 'if(${_d(c)})${_blk(t)}else${_blk(o)}',
      While(cond: final c, body: final b, doWhile: final d) => 'while$d(${_d(c)})${_blk(b)}',
      ForC(init: final i, cond: final c, step: final s, body: final b) =>
        'for(${_d(i)};${_d(c)};${_d(s)})${_blk(b)}',
      ForIn(name: final s, iterable: final i, body: final b) => 'for($s in ${_d(i)})${_blk(b)}',
      Repeat(count: final c, body: final b) => 'repeat(${_d(c)})${_blk(b)}',
      WithS(call: final c, body: final b) => 'with ${_d(c)}${_blk(b)}',
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

/// A single statement and a block with it are the same thing.
String _blk(Stmt? s) => s == null ? '_' : (s is Block ? _d(s) : '{${_d(s)}}');

/// Code of the blocks with every block generated anew (nothing kept from
/// the original text).
String regenerate(String code) {
  final doc = parseBlocks(code);
  for (final n in doc.all) {
    n.src = null;
  }
  return doc.code();
}

const tricky = r'''
// Заголовок
// из двух строк

let a = 5;   // точка с запятой
let b
const c = "x", d = 2
var e = [1, 2,
    3]
a += 2
a++
--a
click(10, 20, button: "right")  // правый
await wait(1s)
if (a > 1) click(1, 2)
if (a) {
    // первый
    log("a")
} else if (b) {
    log("b") /* блок */
} else {
    log("c")
}
if (x) {
} else {
    if (y) {
        log(1)
    }
}
repeat {
    wait(1)
    if (chance(10%)) break
}
repeat (3) { click() }
with_window("notepad|Отчёт", focus: false) {
    click(50%, 50%)
}
with_window("game") { key("e") }
while (!done && i < 10) {
    i = i + 1
    continue
}
do {
    i--
} while (i > 0);
for (let i in 1..10) {
    log(i)
}
for (let j = 0; j < 3; j++) {
    log(j)
}
function farm(n, speed) {
    // фарм
    for (k of [1, 2]) {
        log(k)
    }
    return n * 2
}
async function f2() { return }
try {
    throw "err"
} catch (e) {
    log(e)
} finally {
    log("end")
}
try { x() } catch { }
switch (a) {
    case 1:
        log("one")
        break
    case "two":
    default:
        log("other")
}
let tpl = `a ${a + 1}
b`
let f = (x) => x * 2
let g = () => {
    log("g")
}
obj.list.push(1)
log(`итог: ${a}`, {k: 1, "m": [1]})
if (a) {
    log(1)
} // конец
/* между */ log(2)
if (a) {
    log(1)
}
// перед else
else {
    log(2)
}
''';

void main() {
  final corpus = <String, String>{
    for (final e in exampleScripts.entries) 'пример ${e.key}': e.value,
    for (final e in checkScripts.entries) 'проверка ${e.key}': e.value,
    for (final t in scriptTemplates) 'шаблон ${t.id}': t.build(const {}),
    'сложный': tricky,
  };

  test('нетронутый код переводится в блоки и обратно без изменений', () {
    for (final e in corpus.entries) {
      expect(parseBlocks(e.value).code(), e.value, reason: e.key);
    }
  });

  test('код, заново собранный из блоков, делает то же самое', () {
    for (final e in corpus.entries) {
      final again = regenerate(e.value);
      expect(dump(again), dump(e.value), reason: '${e.key}:\n$again');
      // Repeating gives exactly the same code.
      expect(regenerate(again), again, reason: e.key);
    }
  });

  test('ни один комментарий не теряется', () {
    for (final e in corpus.entries) {
      final again = regenerate(e.value);
      final lexer = Lexer(e.value)..scan();
      for (final c in lexer.comments) {
        final text = e.value.substring(c.start, c.end).trim();
        expect(again, contains(text), reason: '${e.key}: $text');
      }
    }
  });

  test('блоки сложного кода', () {
    final doc = parseBlocks(tricky);
    final kinds = doc.nodes.map((n) => n.kind).toList();
    expect(kinds.take(6), [BK.comment, BK.let, BK.let, BK.code, BK.let, BK.set]);
    expect(doc.nodes.first.text, ' Заголовок\n из двух строк');
    final a = doc.nodes[1];
    expect((a.text, a.args.single, a.semi, a.tail, a.blank), ('a', '5', true, '// точка с запятой', 1));
    expect(doc.nodes[2].args, isEmpty);
    final click = doc.nodes.firstWhere((n) => n.kind == BK.call && n.text == 'click');
    expect(click.args, ['10', '20']);
    expect(click.named, {'button': '"right"'});
    final ifs = doc.nodes.firstWhere((n) => n.kind == BK.ifs && n.args.length == 2);
    expect(ifs.args, ['a', 'b']);
    expect(ifs.hasElse, isTrue);
    expect(ifs.bodies[0].first.kind, BK.comment);
    expect(ifs.bodies[1].single.tail, '/* блок */');
    final nested = doc.nodes.firstWhere((n) => n.kind == BK.ifs && n.args.length == 1 && n.args[0] == 'x');
    expect(nested.bodies.last.single.kind, BK.ifs, reason: 'else { if } остаётся вложенным');
    final forever = doc.nodes.firstWhere((n) => n.kind == BK.repeat);
    expect(forever.args, isEmpty);
    final fn = doc.nodes.firstWhere((n) => n.kind == BK.func);
    expect((fn.text, fn.extra), ('farm', 'n, speed'));
    expect(fn.bodies[0].map((n) => n.kind), [BK.comment, BK.forIn, BK.ret]);
    expect(doc.nodes.where((n) => n.kind == BK.tryc).map((n) => n.extra), ['cf', 'c']);
    final sw = doc.nodes.firstWhere((n) => n.kind == BK.sw);
    expect(sw.args, ['a', '1', '"two"', '']);
    expect(sw.bodies.map((b) => b.length), [2, 0, 1]);
    expect(doc.nodes.where((n) => n.tail == '// конец').single.kind, BK.ifs);
    // The comment between `}` and `else` keeps the whole `if` as code.
    expect(doc.nodes.last.kind, BK.code);
    expect(doc.nodes.last.text, startsWith('if (a) {'));
    // Lines.
    expect(a.line, 4);
    expect(doc.at(fn.line + 3)!.kind, BK.call);
    expect(doc.at(fn.line + 3)!.parent!.kind, BK.forIn);
  });

  test('ошибка в коде — блоков нет', () {
    expect(() => parseBlocks('if (a {'), throwsA(anything));
    expect(parseBlocks('').nodes, isEmpty);
    expect(parseBlocks('').code(), '');
  });

  group('правка блоков', () {
    const code = 'wait(1s)\n\nrepeat (5) {\n    click(50%, 50%)  // центр\n    wait(500)\n}\nlog("Готово")\n';

    test('изменить параметр', () {
      final doc = parseBlocks(code);
      final click = doc.all.firstWhere((n) => n.text == 'click');
      click.args[0] = '10%';
      click.named['button'] = '"right"';
      BlockDoc.touch(click);
      expect(doc.code(),
          'wait(1s)\n\nrepeat (5) {\n    click(10%, 50%, button: "right")  // центр\n    wait(500)\n}\nlog("Готово")\n');
    });

    test('вставить, перенести и удалить', () {
      final doc = parseBlocks(code);
      final rep = doc.nodes[1];
      doc.insert(rep, 0, 2, parseSnippet('key("enter")'));
      expect(doc.code(), contains('    wait(500)\n    key("enter")\n}'));
      final log = doc.nodes.last;
      expect(doc.move(log, rep, 0, 0), isTrue);
      expect(doc.code(),
          'wait(1s)\n\nrepeat (5) {\n    log("Готово")\n    click(50%, 50%)  // центр\n    wait(500)\n    key("enter")\n}\n');
      expect(doc.move(rep, rep, 0, 0), isFalse, reason: 'в самого себя нельзя');
      doc.remove(rep);
      expect(doc.code(), 'wait(1s)\n');
      expect(parseBlocks(doc.code()).nodes.single.text, 'wait');
    });

    test('перенос внутри одного списка', () {
      final doc = parseBlocks('a()\nb()\nc()\n');
      doc.move(doc.nodes[0], null, 0, 3);
      expect(doc.code(), 'b()\nc()\na()\n');
      doc.move(doc.nodes[2], null, 0, 0);
      expect(doc.code(), 'a()\nb()\nc()\n');
    });

    test('блок, перенесённый глубже, сдвигает свои строки', () {
      final doc = parseBlocks('if (a) {\n    log(1)\n}\nrepeat {\n}\n');
      doc.move(doc.nodes[0], doc.nodes[1], 0, 0);
      expect(doc.code(), 'repeat {\n    if (a) {\n        log(1)\n    }\n}\n');
    });

    test('новые блоки: условия, циклы, функции', () {
      final doc = parseBlocks('');
      doc.insert(null, 0, 0, parseSnippet('if (true) {\n} else {\n}'));
      doc.insert(doc.nodes[0], 1, 0, parseSnippet('wait(1s)'));
      doc.insert(null, 0, 1, parseSnippet('function my_action() {\n}'));
      expect(doc.code(), 'if (true) {\n} else {\n    wait(1s)\n}\nfunction my_action() {\n}\n');
      expect(dump(doc.code()), dump('if (true) {} else { wait(1s) } function my_action() {}'));
    });

    test('комментарий: правка текста', () {
      final doc = parseBlocks('// старый\nclick()\n');
      doc.nodes[0].text = ' новый\n вторая строка';
      BlockDoc.touch(doc.nodes[0]);
      expect(doc.code(), '// новый\n// вторая строка\nclick()\n');
    });
  });

  group('выражения в гнёздах', () {
    test('виды', () {
      expect(shapeOf('50%'), isA<XNum>());
      expect(shapeOf('-3'), isA<XNum>());
      expect(shapeOf('800..1200'), isA<XNum>());
      expect(shapeOf('1s'), isA<XNum>());
      expect((shapeOf('"a\\"b"') as XStr).value, 'a"b');
      expect((shapeOf('#FF0000') as XStr).value, '#FF0000');
      expect((shapeOf('true') as XBool).value, isTrue);
      expect(shapeOf('null'), isA<XNull>());
      expect((shapeOf('count') as XVar).name, 'count');
      final call = shapeOf('pixel_is(x, y, "#FFF", tolerance: 5)') as XCall;
      expect(call.name, 'pixel_is');
      expect(call.args, ['x', 'y', '"#FFF"']);
      expect(call.named, {'tolerance': '5'});
      final op = shapeOf('a + b * c') as XOp;
      expect((op.op, op.left, op.right), ('+', 'a', 'b * c'));
      final and = shapeOf('(a || b) && !c') as XOp;
      expect((and.op, and.left, and.right), ('&&', '(a || b)', '!c'));
      expect((shapeOf('!found') as XNot).operand, 'found');
      expect(shapeOf('pos.x'), isA<XRaw>());
      expect(shapeOf('(a + b)'), isA<XRaw>());
      expect((shapeOf('click(') as XRaw).valid, isFalse);
      expect(shapeOf(''), isA<XEmpty>());
    });

    test('сборка со скобками', () {
      expect(buildOp('&&', 'a || b', 'c'), '(a || b) && c');
      expect(buildOp('||', 'a && b', 'c'), 'a && b || c');
      expect(buildOp('-', 'a', 'b - c'), 'a - (b - c)');
      expect(buildOp('*', '(a + b)', 'c'), '(a + b) * c');
      expect(buildOp('==', 'pixel(1, 2)', '"#FFFFFF"'), 'pixel(1, 2) == "#FFFFFF"');
      expect(buildNot('found'), '!found');
      expect(buildNot('a == b'), '!(a == b)');
      expect(quote('a"b\\c\nd'), r'"a\"b\\c\nd"');
      expect(isValidExpr('1 +'), isFalse);
      expect(isValidExpr('f(1)'), isTrue);
      expect(isValidExpr('1; 2'), isFalse);
    });
  });

  group('каталог', () {
    final rt = ScriptRuntime(StubBackend(), {'main': 't', 'source': ''}, (_) {}, random: Random(1));

    test('у каждой функции движка из подсказок есть блок, и наоборот', () {
      final names = functionSpecs.map((f) => f.name).toSet();
      expect(names.length, functionSpecs.length, reason: 'повторы');
      for (final c in completions.where((c) => c.isFunction)) {
        expect(names, contains(c.name), reason: c.name);
      }
      for (final f in functionSpecs) {
        expect(rt.interp.globals.has(f.name), isTrue, reason: f.name);
        expect(f.hint, isNotEmpty, reason: f.name);
        expect(blockCats.map((c) => c.id), contains(f.cat), reason: f.name);
      }
      expect(specFor('waitPixel')!.name, 'wait_pixel');
    });

    test('подписи и параметры согласованы', () {
      for (final f in functionSpecs) {
        final holes = RegExp(r'\{(\w+)\}').allMatches(f.label).map((m) => m[1]!).toList();
        final params = f.params.map((p) => p.name).toList();
        for (final h in holes) {
          expect(params, contains(h), reason: '${f.name}: {$h}');
        }
        var optional = false;
        for (final p in f.params) {
          if (optional) expect(p.optional, isTrue, reason: '${f.name}.${p.name}: после необязательного');
          optional = optional || p.optional;
          expect(isValidExpr(p.def), isTrue, reason: '${f.name}.${p.name}');
        }
        for (final n in f.named) {
          expect(namedParams, contains(n), reason: '${f.name}: $n');
          expect(paramHints, contains(n), reason: n);
        }
        if (!f.statement) expect(f.isValue, isTrue, reason: f.name);
      }
      for (final p in namedParams.values) {
        expect(isValidExpr(p.def), isTrue, reason: p.name);
        for (final o in p.options.keys) {
          expect(isValidExpr(o), isTrue, reason: '${p.name}: $o');
        }
      }
    });

    test('блоки палитры — правильный код', () {
      for (final c in blockCats) {
        for (final item in paletteFor(c.id, functions: {'farm': ['n']})) {
          if (item.value) {
            expect(isValidExpr(item.code), isTrue, reason: item.code);
          } else {
            final nodes = parseSnippet(item.code);
            expect(nodes.length, 1, reason: item.code);
            expect(nodes.single.kind, isNot(BK.code), reason: item.code);
          }
        }
      }
      for (final f in functionSpecs) {
        final shape = shapeOf(f.example);
        expect(shape, isA<XCall>(), reason: f.example);
        expect((shape as XCall).name, f.name);
      }
    });

    test('свои функции и переменные', () {
      final doc = parseBlocks('let n = 1\nfunction farm(a, b) {\n    for (i in 1..a) { }\n}\n');
      expect(userFunctions(doc), {'farm': ['a', 'b']});
      expect(variableNames(doc), ['a', 'b', 'i', 'n']);
      expect(paletteFor('funcs', functions: userFunctions(doc)).single.code, 'farm(0, 0)');
    });
  });
}
