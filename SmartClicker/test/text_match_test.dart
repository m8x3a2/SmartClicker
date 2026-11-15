// Loose comparison of recognized text: similar, similarity and errors: of
// text_in / wait_text.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/core/engine/runtime.dart';
import 'package:smart_clicker/core/vision/text_match.dart';
import 'package:smart_clicker/platform/stub_backend.dart';

Future<(List<String>, Map<String, Object?>)> _run(String source, {String screen = ''}) async {
  final b = StubBackend()..screenText = screen;
  final events = <Map<String, Object?>>[];
  final rt = ScriptRuntime(b, {'main': 't', 'source': source}, events.add, random: Random(1));
  final result = await rt.runMain();
  return (
    [
      for (final e in events)
        if (e['t'] == 'log' && e['lv'] == 'info') '${e['m']}'
    ],
    result
  );
}

void main() {
  test('расстояние между словами и части текста', () {
    expect(textDistance('враv', 'враг'), 1);
    expect(textDistance('начать игру', 'начать', part: true), 0);
    expect(textDistance('начать игру', 'начать'), 5);
    expect(textDistance('нчать', 'начать'), 1); // missing letter
    expect(textDistance('', 'abc'), 3);
    expect(autoErrors(4), 1);
    expect(autoErrors(3), 0);
    expect(autoErrors(16), 4);
  });

  test('similar: ошибки, регистр, похожие буквы, процент', () {
    expect(textMatches('Враv', 'враг'), isTrue); // 1 mistake in 4 letters
    expect(textMatches('Bpaг', 'враг'), isTrue); // look-alike Latin letters
    expect(textMatches('Bpaг', 'враг', const MatchRules(lookalike: false, errors: 1)), isFalse);
    expect(textMatches('Начать игру', 'НАЧАТЬ'), isTrue);
    expect(textMatches('Начать игру', 'НАЧАТЬ', const MatchRules(exactCase: true)), isFalse);
    expect(textMatches('Начать игру', 'Начать', const MatchRules(part: false)), isFalse);
    expect(textMatches('Нчать', 'Начать', const MatchRules(errors: 0)), isFalse);
    expect(textMatches('Выход', 'Начать'), isFalse);
    expect(textMatches('Нача', 'Начать', const MatchRules(percent: 60)), isTrue);
    expect(textMatches('Нача', 'Начать', const MatchRules(percent: 80)), isFalse);
    expect(textSimilarity('Начать', 'начать'), 100);
    expect(textSimilarity('Нача', 'Начать'), 67);
    expect(textSimilarity('xyz', 'Начать'), 0);
  });

  test('в скрипте: similar, similarity и errors: у text_in', () async {
    final (logs, r) = await _run('''
let t = "Враv атакует"
log(similar(t, "враг"), similar(t, "враг", errors: 0), similar(t, "друг"))
log(similar(null, "враг"), similarity("Нача", "Начать"))
log(similar("Начать", "начать", case: "exact", errors: 0), similar("Начать", "Начать", case: "exact", errors: 0))
log(text_in(0, 0, 100, 20, "враг"), text_in(0, 0, 100, 20, "враг", errors: 1))
log(wait_text(0, 0, 100, 20, "атакуeт", timeout: 100, interval: 50, errors: 1))
''', screen: 'Враv атакует');
    expect(r['error'], isNull, reason: '$r');
    expect(logs, [
      'true false false',
      'false 67',
      'false true',
      'false true',
      'true',
    ]);
    final (_, bad) = await _run('similar("a", "b", case: "upside")');
    expect('${bad['error']}', contains('case'));
  });
}
