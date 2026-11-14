// Undo / redo of a script: grouping of typing, a new edit after undo, the
// limit, and Ctrl+Z / Ctrl+Y in the real code editor.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/app/state/edit_history.dart';
import 'package:smart_clicker/app/ui/editor/code_editor.dart';

TextEditingValue v(String t) => TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));

void main() {
  test('набор подряд — один шаг, Enter и вставка — отдельные шаги', () {
    var now = DateTime(2026);
    final h = EditHistory(clock: () => now);
    h.record(v(''));
    for (final t in ['c', 'cl', 'cli', 'clic', 'click']) {
      now = now.add(const Duration(milliseconds: 200));
      h.record(v(t));
    }
    now = now.add(const Duration(milliseconds: 200));
    h.record(v('click\n')); // Enter
    now = now.add(const Duration(milliseconds: 200));
    h.record(v('click\nwait(1s)')); // paste
    expect(h.undo()!.text, 'click\n');
    expect(h.undo()!.text, 'click');
    expect(h.undo()!.text, '');
    expect(h.undo(), isNull);
    expect(h.redo()!.text, 'click');

    // A pause in typing starts a new step.
    final g = EditHistory(clock: () => now);
    g.record(v(''));
    g.record(v('a'));
    now = now.add(const Duration(milliseconds: 100));
    g.record(v('ab'));
    now = now.add(const Duration(seconds: 3));
    g.record(v('abc'));
    expect(g.undo()!.text, 'ab');
    expect(g.undo()!.text, '');
  });

  test('новая правка после отмены убирает шаги вперёд; только курсор — не шаг; лимит', () {
    final h = EditHistory();
    h.record(v('a'));
    h.record(v('a b c'));
    h.record(v('a b c d e'));
    h.undo();
    h.record(v('a b c X Y'));
    expect(h.canRedo, isFalse);
    h.record(const TextEditingValue(text: 'a b c X Y', selection: TextSelection.collapsed(offset: 1)));
    expect(h.undo()!.text, 'a b c');

    final small = EditHistory(limit: 3);
    for (final t in ['1', '1 2 3', '1 2 3 4 5', '1 2 3 4 5 6 7']) {
      small.record(v(t));
    }
    expect(small.length, 3);
  });

  testWidgets('Ctrl+Z и Ctrl+Y в редакторе идут через историю скрипта', (tester) async {
    final c = CodeController()..text = 'log(1)';
    final h = EditHistory()..record(c.value);
    c.addListener(() => h.record(c.value));
    var applying = false;
    void apply(TextEditingValue? x) {
      if (x == null) return;
      applying = true;
      c.value = x;
      applying = false;
    }

    expect(applying, isFalse);
    final line = ValueNotifier<int>(0);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CodeEditor(
            controller: c,
            currentLine: line,
            errorLine: line,
            onUndo: () => apply(h.undo()),
            onRedo: () => apply(h.redo())),
      ),
    ));
    await tester.showKeyboard(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'log(1)\nwait(1s)');
    await tester.pump();
    Future<void> ctrl(LogicalKeyboardKey k, {bool shift = false}) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(k);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    await ctrl(LogicalKeyboardKey.keyZ);
    expect(c.text, 'log(1)');
    await ctrl(LogicalKeyboardKey.keyY);
    expect(c.text, 'log(1)\nwait(1s)');
    await ctrl(LogicalKeyboardKey.keyZ);
    await ctrl(LogicalKeyboardKey.keyZ, shift: true);
    expect(c.text, 'log(1)\nwait(1s)');
  });
}
