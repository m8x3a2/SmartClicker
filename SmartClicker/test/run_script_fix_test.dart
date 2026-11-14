// After a rename: the window that asks which run_script calls to fix, and
// the check that warns about a short name that fits several scripts.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/app/state/app_controller.dart';
import 'package:smart_clicker/app/ui/scripts/run_script_fix_dialog.dart';
import 'package:smart_clicker/core/lang/checker.dart';
import 'package:smart_clicker/core/lang/script_refs.dart';

void main() {
  testWidgets('окно: все отмечены, снять один, исправить остальные', (tester) async {
    const before = ['old/x', 'A', 'B'];
    const after = ['new/x', 'A', 'B'];
    const renames = {'old/x': 'new/x'};
    final fixes = <RunScriptFix>[
      for (final (s, text) in [('A', 'run_script("old/x")\nrun_script("x")'), ('B', 'run_script("x")')])
        for (final c in fixScriptRefs(text, renames, before, after).changes)
          RunScriptFix(s, c, text.split('\n')[c.line - 1]),
    ];
    // "x" (short) still finds the moved script, the old full path does not.
    expect(fixes.map((f) => (f.script, f.change.line, f.change.broken)),
        [('A', 1, true), ('A', 2, false), ('B', 1, false)]);

    List<RunScriptFix>? got;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => got = await showRunScriptFixDialog(context, fixes),
          child: const Text('go'),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Исправить (3)'), findsOneWidget);
    expect(find.textContaining('⚠ стр. 1'), findsOneWidget);

    await tester.tap(find.text('Снять все'));
    await tester.pump();
    expect(find.text('Исправить (0)'), findsOneWidget);
    await tester.tap(find.text('Отметить все'));
    await tester.pump();
    await tester.tap(find.byType(Checkbox).at(1)); // A, line 2
    await tester.pump();
    await tester.tap(find.text('Исправить (2)'));
    await tester.pumpAndSettle();
    expect(got!.map((f) => (f.script, f.change.line)), [('A', 1), ('B', 1)]);
  });

  test('проверка: короткое имя подходит к нескольким скриптам — замечание', () {
    final scripts = {'night 2': 'log(1)', 'temp/night 2': 'log(2)', 'Фарм/Бой': 'log(3)'};
    List<Issue> check(String src) => checkScript(
        src,
        CheckContext(
          builtins: AppController.builtinNames,
          scriptSource: (n) => scripts[resolveScriptName(n, scripts.keys)],
          imageExists: (_) => true,
          scriptNames: scripts.keys.toList(),
        ));
    final w = check('run_script("night 2")').single;
    expect(w.error, isFalse);
    expect(w.message, contains('"night 2", "temp/night 2"; будет запущен "night 2"'));
    expect(check('run_script("temp/night 2")\nrun_script("Бой")'), isEmpty);
  });
}
