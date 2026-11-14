import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/app/state/app_controller.dart';
import 'package:smart_clicker/app/templates/script_templates.dart';
import 'package:smart_clicker/core/lang/checker.dart';

void main() {
  List<Issue> check(String src) => checkScript(
      src,
      CheckContext(
        builtins: AppController.builtinNames,
        scriptSource: (_) => null,
        imageExists: (_) => true,
      ));

  test('все шаблоны дают код без ошибок и замечаний', () {
    final ids = <String>{};
    for (final t in scriptTemplates) {
      expect(ids.add(t.id), isTrue, reason: t.id);
      expect(t.validate(t.defaults), isEmpty, reason: t.id);
      final code = t.build(const {});
      expect(check(code), isEmpty, reason: '${t.id}:\n$code');
    }
  });

  test('значения подставляются, кавычки экранируются, поля проверяются', () {
    final clicker = scriptTemplates.firstWhere((t) => t.id == 'clicker');
    expect(clicker.build({'count': '5', 'point': '100, 200', 'pause': '250'}),
        allOf(contains('repeat (5) {'), contains('click(100, 200)'), contains('wait(250)')));
    expect(clicker.build({'count': '0'}), contains('repeat {'));
    expect(clicker.validate({'pause': 'abc', 'point': ' '}).keys, {'pause', 'point'});

    final text = scriptTemplates.firstWhere((t) => t.id == 'wait_text');
    final code = text.build({'text': 'Сказал "да"'});
    expect(code, contains(r'"Сказал \"да\""'));
    expect(check(code), isEmpty);

    final pixel = scriptTemplates.firstWhere((t) => t.id == 'pixel');
    expect(pixel.validate({'color': 'зелёный'}).keys, {'color'});
    expect(pixel.build({'color': 'a0b0c0'}), contains('"#A0B0C0"'));
    expect(q(r'a\b'), r'"a\\b"');
  });
}
