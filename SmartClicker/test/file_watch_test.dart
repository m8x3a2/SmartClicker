// Автозапуск «По файлу»: when a change of a file starts a script (settling,
// deleted files, JSON key, not too often), and saving the rules.

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/core/automation/file_watch.dart';

void main() {
  final t0 = DateTime(2026, 11, 15, 5);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  test('изменение засчитывается, когда файл успокоился; начальное состояние — не изменение', () {
    final w = FileWatch();
    final r = FileRule(script: 'Бой', path: 'задание.json');
    var stamp = 'a';
    List<FileEvent> step(int ms) =>
        [for (final e in w.check([r], (_) => stamp, (_, _) => true, at(ms))) e.$2];

    expect(step(0), isEmpty); // what is there at the start
    expect(step(1000), isEmpty);
    stamp = 'b';
    expect(step(2000), isEmpty); // just changed: waits
    stamp = 'c'; // still being written
    expect(step(2500), isEmpty);
    expect(step(3000), isEmpty); // less than 1 s since the last change
    expect(step(3600), [FileEvent.fire]);
    expect(step(4600), isEmpty); // handled once
  });

  test('удалённый файл не запускает, появившийся снова — запускает', () {
    final w = FileWatch();
    final r = FileRule(script: 'Бой', path: 'задание.json', minGapSec: 0);
    var stamp = 'a';
    List<FileEvent> step(int ms) =>
        [for (final e in w.check([r], (_) => stamp, (_, _) => true, at(ms))) e.$2];
    step(0);
    stamp = '';
    step(1000);
    expect(step(2100), isEmpty);
    stamp = 'b';
    step(3000);
    expect(step(4100), [FileEvent.fire]);
  });

  test('ключ JSON, «не чаще раза в N с», выключенное правило', () {
    final w = FileWatch();
    final r = FileRule(script: 'Бой', path: 'задание.json', key: 'ready', minGapSec: 60);
    var stamp = 'a';
    var ready = false;
    List<FileEvent> step(int ms) =>
        [for (final e in w.check([r], (_) => stamp, (_, k) => k == 'ready' && ready, at(ms))) e.$2];
    step(0);
    stamp = 'b';
    step(1000);
    expect(step(2100), [FileEvent.notReady]);
    stamp = 'c';
    ready = true;
    step(3000);
    expect(step(4100), [FileEvent.fire]);
    r.lastRun = at(4100);
    stamp = 'd';
    step(5000);
    expect(step(6100), [FileEvent.tooSoon]);

    r.enabled = false;
    stamp = 'e';
    step(7000);
    expect(step(8100), isEmpty);
  });

  test('правило сохраняется и читается', () {
    final r = FileRule(
        script: 'Папка/Бой', path: 'задание.json', key: 'ready', mode: FileRunMode.test, minGapSec: 5);
    final back = FileRule.fromJson(r.toJson());
    expect(back.script, 'Папка/Бой');
    expect(back.key, 'ready');
    expect(back.mode, FileRunMode.test);
    expect(back.minGapSec, 5);
    expect(FileRule.fromJson({'script': 'a', 'path': 'b', 'mode': '???'}).mode, FileRunMode.ask);
    expect(r.describe(), contains('ready'));
    expect(r.describe(), contains('тестовом'));
  });
}
