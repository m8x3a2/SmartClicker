// Statistics of scripts from the run history.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/app/state/app_controller.dart';
import 'package:smart_clicker/app/state/script_stats.dart';
import 'package:smart_clicker/app/ui/history/script_stats_view.dart';

RunRecord rec(String s, int minute, int ms, String status, [String? error]) =>
    RunRecord(s, DateTime(2026, 11, 15, 10, minute), ms, status, error, null);

void main() {
  final history = [
    rec('Фарм', 50, 4000, 'error', 'картинка "ок" не найдена'),
    rec('Почта', 40, 1000, 'ok'),
    rec('Фарм', 30, 2000, 'error', 'картинка "ок" не найдена'),
    rec('Фарм', 20, 6000, 'stopped'),
    rec('Фарм', 10, 1000, 'error', 'нет окна'),
    rec('Фарм', 5, 3000, 'ok'),
  ];

  test('счёт по скриптам: запуски, исходы, время, частая ошибка', () {
    final all = scriptStats(history);
    expect(all.map((s) => s.script), ['Фарм', 'Почта']); // the latest first
    final f = all.first;
    expect([f.runs, f.ok, f.errors, f.stopped], [5, 1, 3, 1]);
    expect([f.totalMs, f.averageMs, f.longestMs], [16000, 3200, 6000]);
    expect(f.last.started.minute, 50);
    expect(f.topError, 'картинка "ок" не найдена');
    expect(f.topErrorCount, 2);
    expect(all.last.topError, isNull);
    expect(scriptStats(const []), isEmpty);
  });

  test('склонение «запусков»', () {
    expect([1, 2, 5, 11, 21, 22, 112].map(runsWord).toList(),
        ['1 запуск', '2 запуска', '5 запусков', '11 запусков', '21 запуск', '22 запуска', '112 запусков']);
  });

  testWidgets('карточка показывает главное', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ScriptStatsCard(scriptStats(history).first))));
    expect(find.textContaining('5 запусков · успешно 1 · с ошибкой 3 · остановлено 1'), findsOneWidget);
    expect(find.textContaining('Частая ошибка (×2): картинка "ок" не найдена'), findsOneWidget);
    expect(find.textContaining('последний: 15.11 10:50:00 — ошибка'), findsOneWidget);
  });
}
