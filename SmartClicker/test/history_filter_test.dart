// History of runs: filters (script, period, result, how started, text),
// order, days for "go to", the error line, and the new fields kept on disk.

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/app/state/app_controller.dart';
import 'package:smart_clicker/app/state/history_filter.dart';
import 'package:smart_clicker/core/storage/settings.dart';

void main() {
  final now = DateTime(2026, 11, 15, 20);
  RunRecord run(String script, DateTime at, String status,
          {int ms = 1000, String? error, String via = 'manual', String? source}) =>
      RunRecord(script, at, ms, status, error, null, via: via, source: source);

  final runs = [
    run('Бой', DateTime(2026, 11, 15, 10), 'ok', ms: 5000, via: 'schedule', source: 'click(1, 2)'),
    run('Бой', DateTime(2026, 11, 14, 22), 'error', error: 'Строка 7: картинки нет', via: 'key'),
    run('Фарм', DateTime(2026, 11, 14, 9), 'stopped', ms: 90000, via: 'tray'),
    run('Фарм', DateTime(2026, 11, 1, 9), 'closed', via: 'file'),
  ];

  List<String> names(HistoryFilter f) =>
      [for (final r in f.apply(runs, now)) '${r.script} ${r.started.day}'];

  test('без фильтров — всё, новые сверху', () {
    expect(names(HistoryFilter()), ['Бой 15', 'Бой 14', 'Фарм 14', 'Фарм 1']);
    expect(HistoryFilter().active, isFalse);
  });

  test('скрипт, период, результат, способ запуска', () {
    expect(names(HistoryFilter()..script = 'Фарм'), ['Фарм 14', 'Фарм 1']);
    expect(names(HistoryFilter()..period = HistoryPeriod.today), ['Бой 15']);
    expect(names(HistoryFilter()..period = HistoryPeriod.yesterday), ['Бой 14', 'Фарм 14']);
    expect(names(HistoryFilter()..period = HistoryPeriod.week), ['Бой 15', 'Бой 14', 'Фарм 14']);
    expect(
        names(HistoryFilter()
          ..period = HistoryPeriod.days
          ..from = DateTime(2026, 11, 1)
          ..to = DateTime(2026, 11, 14)),
        ['Бой 14', 'Фарм 14', 'Фарм 1']);
    expect(names(HistoryFilter()..result = 'error'), ['Бой 14']);
    expect(names(HistoryFilter()..result = 'other'), ['Фарм 1']);
    expect(names(HistoryFilter()..via = 'manual'), ['Фарм 14'], reason: 'трей — это «вручную»');
    expect(names(HistoryFilter()..via = 'schedule'), ['Бой 15']);
  });

  test('поиск: ошибка, имя, текст скрипта, лог; сортировка', () {
    expect(names(HistoryFilter()..query = 'КАРТИНКИ'), ['Бой 14']);
    expect(names(HistoryFilter()..query = 'click('), ['Бой 15']);
    final withLog = [RunRecord('Лог', DateTime(2026, 11, 15), 1, 'ok', null, 'a.log')];
    final f = HistoryFilter()..query = 'дождался';
    expect(f.apply(withLog, now, logText: (_) => 'Дождался 4:10'), isEmpty);
    f.inLogs = true;
    expect(f.apply(withLog, now, logText: (_) => 'Дождался 4:10').length, 1);
    expect(names(HistoryFilter()..sort = HistorySort.longest).first, 'Фарм 14');
    expect(names(HistoryFilter()..sort = HistorySort.oldest).first, 'Фарм 1');
  });

  test('дни для «Перейти к…», строка ошибки, сброс', () {
    expect([for (final (d, n) in historyDays(runs)) '${d.day}:$n'], ['15:1', '14:2', '1:1']);
    expect(errorLineOf(runs[1]), 7);
    expect(errorLineOf(runs[0]), 0);
    final f = HistoryFilter()
      ..script = 'Бой'
      ..query = 'x';
    expect(f.active, isTrue);
    f.reset();
    expect(f.active, isFalse);
  });

  test('способ запуска, тестовый режим и текст скрипта сохраняются', () {
    final r = RunRecord('Бой', DateTime(2026), 10, 'ok', null, null,
        report: 'r.zip', via: 'key', dry: true, source: 'log(1)');
    final back = RunRecord.fromJson(r.toJson());
    expect([back.via, back.dry, back.source, back.report], ['key', true, 'log(1)', 'r.zip']);
    final old = RunRecord.fromJson({'script': 'a', 'started': '2026-01-01', 'status': 'ok'});
    expect([old.via, old.dry, old.source], ['', false, null]);
    expect(Settings().historyKeepSource, isTrue);
  });
}
