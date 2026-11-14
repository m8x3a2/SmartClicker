import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/core/lang/completions.dart';
import 'package:smart_clicker/app/help/help_texts.dart';
import 'package:smart_clicker/core/vision/image.dart';
import 'package:smart_clicker/app/ui/help/help_screen.dart';
import 'package:smart_clicker/core/engine/runtime.dart';
import 'package:smart_clicker/platform/stub_backend.dart';
import 'package:smart_clicker/app/ui/editor/code_editor.dart';

void main() {
  test('каждая подсказка — настоящая функция движка', () {
    final rt = ScriptRuntime(
        StubBackend(), {'main': 't', 'source': ''}, (_) {},
        random: Random(1));
    for (final c in completions.where((c) => c.isFunction)) {
      expect(rt.interp.globals.has(c.name), isTrue, reason: c.name);
      expect(c.signature.startsWith('${c.name}('), isTrue, reason: c.name);
    }
  });

  test('подбор подсказок', () {
    expect(suggest('cl').map((c) => c.name), containsAll(['click', 'clock']));
    expect(suggest('wait').map((c) => c.name), ['wait_until', 'wait_pixel', 'wait_text', 'wait_image']);
    expect(suggest('pixel').map((c) => c.name).first, 'pixel_is');
    expect(suggest('zz'), isEmpty);
    final own = scriptFunctions('function farm(n, speed) { }');
    expect(own.single.signature, 'farm(n, speed)');
    expect(suggest('fa', own).first.name, 'farm');
    expect(completionFor('waitPixel')!.name, 'wait_pixel');
    expect(completionFor('repeat'), isNull);
    expect(completions.firstWhere((c) => c.name == 'click').insert, 'click(|)');
    expect(completions.firstWhere((c) => c.name == 'exit').insert, 'exit()');
  });

  test('поиск в тексте без учёта регистра', () {
    final c = CodeController()..text = 'Click(1)\nclick(2)\nCLICK(3) a.b';
    expect(c.matches, isEmpty);
    c.query = 'click';
    expect(c.matches.map((m) => m.start), [0, 9, 18]);
    c.query = 'a.b'; // not a regular expression
    expect(c.matches.length, 1);
    c.text = 'axb';
    expect(c.matches, isEmpty);
  });

  Future<CodeController> pumpEditor(WidgetTester tester, String text) async {
    final c = CodeController()..text = text;
    final line = ValueNotifier<int>(0);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CodeEditor(controller: c, currentLine: line, errorLine: line),
      ),
    ));
    await tester.showKeyboard(find.byType(TextField));
    await tester.pump();
    return c;
  }

  testWidgets('подсказка при наборе вставляется по Tab', (tester) async {
    final c = await pumpEditor(tester, '');
    await tester.enterText(find.byType(TextField), 'wait_p');
    await tester.pump();
    expect(find.textContaining('wait_pixel(x, y'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(c.text, 'wait_pixel()');
    expect(c.selection.baseOffset, 'wait_pixel('.length);
  });

  testWidgets('Enter сохраняет отступ и углубляет после {', (tester) async {
    final c = await pumpEditor(tester, '');
    await tester.enterText(find.byType(TextField), '    repeat (3) {');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(c.text, '    repeat (3) {\n        ');
  });

  testWidgets('поиск и замена всех вхождений', (tester) async {
    final c = await pumpEditor(tester, 'wait(1)\nclick(1, 1)\nwait(1)');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3));
    await tester.enterText(fields.at(1), 'WAIT');
    await tester.pump();
    expect(find.text('1 из 2'), findsOneWidget);
    await tester.enterText(fields.at(2), 'pause');
    await tester.tap(find.text('Заменить все'));
    await tester.pump();
    expect(c.text, 'pause(1)\nclick(1, 1)\npause(1)');
    expect(find.text('заменено: 2'), findsOneWidget);
  });

  test('имя картинки под мышью и размер PNG', () {
    const line = '    if (click_image("старт", timeout: 5s)) { log("старт") }';
    final at = line.indexOf('"старт"');
    expect(pictureNameAt(line, at + 2), (name: 'старт', start: at));
    expect(pictureNameAt(line, at), isNotNull); // on the quote itself
    expect(pictureNameAt(line, at - 2), isNull); // on the function name
    expect(pictureNameAt(line, line.lastIndexOf('старт')), isNull); // log("старт")
    expect(pictureNameAt("waitImage('кнопка.png')", 12)?.name, 'кнопка.png');
    expect(pictureNameAt('screenshot("", 0, 0, 5, 5)', 12), isNull);
    final png = pngEncode(Bitmap(7, 3, Uint8List(7 * 3 * 4)));
    expect(pngSize(png), (w: 7, h: 3));
    expect(pngSize(Uint8List(30)), isNull);
  });

  test('справка: разделы и команды из руководств существуют', () {
    expect(helpSections.map((s) => s.title).toSet().length, helpSections.length);
    expect(helpSections.where((s) => s.text == null).length, 1); // notes
    const keywords = {'if', 'while', 'for', 'function', 'switch', 'catch'};
    for (final guide in [imageGuide, beginnerGuide, blocksGuide]) {
      for (final line in guide.split('\n')) {
        if (!line.startsWith('    ')) continue; // code lines are indented
        for (final m in RegExp(r'([A-Za-z_]\w*)\(').allMatches(line)) {
          final name = m[1]!;
          if (keywords.contains(name)) continue;
          expect(completionFor(name), isNotNull, reason: '$name в строке: $line');
        }
      }
    }
  });
}
