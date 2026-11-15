// Search in all scripts: lines and places of matches, case, whole word,
// order of scripts, the limit.

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/core/lang/script_search.dart';

void main() {
  final scripts = {
    'Фарм': 'click_image("враг")\nwait(1s)\r\nclick(50%, 50%)',
    'Бой': 'let Враг = 1\nclick(10, 10)',
  };

  test('строки и места совпадений, скрипты по имени', () {
    final hits = searchScripts(scripts, 'click');
    expect([for (final h in hits) '${h.script}:${h.line}:${h.start}'], ['Бой:2:0', 'Фарм:1:0', 'Фарм:3:0']);
    expect(hits.last.text, 'click(50%, 50%)', reason: 'без \\r');
  });

  test('регистр и слово целиком', () {
    expect(searchScripts(scripts, 'враг').length, 2);
    expect(searchScripts(scripts, 'враг', caseSensitive: true).single.script, 'Фарм');
    expect(searchScripts(scripts, 'click', wholeWord: true).length, 2, reason: 'click_image — другое слово');
    expect(searchScripts(scripts, ''), isEmpty);
    expect(searchScripts(scripts, '50%').length, 2, reason: 'знаки ищутся как есть, оба в одной строке');
  });

  test('не больше $searchLimit совпадений', () {
    final many = {'a': List.filled(600, 'x').join('\n')};
    expect(searchScripts(many, 'x').length, searchLimit);
  });
}
