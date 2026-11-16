// «Сторож»: a crash or a hang of the program → close, start again, wait,
// start the script; limits and giving up. Pure logic, the time is passed.

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/core/automation/game_guard.dart';

void main() {
  final t0 = DateTime(2026, 11, 16, 3, 0, 0);
  DateTime at(int s) => t0.add(Duration(seconds: s));

  GuardRule rule({String launch = r'C:\Games\game.exe', int hang = 30, int load = 10, int max = 3}) =>
      GuardRule(process: 'game.exe', script: 'Фарм', launch: launch, hangSec: hang, loadSec: load, maxPerHour: max);

  /// Runs the guard second by second; [seenAt] gives the program state.
  List<String> run(GuardWatch w, GuardRule r, int from, int to, GuardSeen Function(int s) seenAt,
      {bool armed = true, bool busy = false}) => [
        for (var s = from; s <= to; s++)
          for (final step in w.check([r], (_) => armed, (_) => seenAt(s), busy, at(s))) '$s ${step.act.name}',
      ];

  const ok = (running: true, hung: false);
  const gone = (running: false, hung: false);
  const hung = (running: true, hung: true);

  test('вылет: закрыть, запустить, дождаться окна и загрузки, запустить скрипт', () {
    final w = GuardWatch(), r = rule();
    // runs; disappears at 10; comes back at 20 (after the launch); loads 10 s
    final steps = run(w, r, 0, 40, (s) => s < 10 ? ok : (s < 20 ? gone : ok));
    expect(steps, ['13 stopAndClose', '15 launch', '30 runScript']);
    expect(r.restarts, [at(13)]);
    expect(w.busy(r), isFalse);
  });

  test('короткое исчезновение (перезапуск самой программой) — не вылет', () {
    final w = GuardWatch(), r = rule();
    expect(run(w, r, 0, 20, (s) => s == 5 || s == 6 ? gone : ok), isEmpty);
  });

  test('зависание дольше hangSec; 0 — не проверяется', () {
    final w = GuardWatch(), r = rule(hang: 5);
    final steps = run(w, r, 0, 12, (s) => s >= 3 ? hung : ok);
    expect(steps.first, '8 stopAndClose');
    final w2 = GuardWatch(), r2 = rule(hang: 0);
    expect(run(w2, r2, 0, 60, (_) => hung), isEmpty);
  });

  test('сторож молчит, пока не взведён (скрипт не работает)', () {
    final w = GuardWatch(), r = rule();
    expect(run(w, r, 0, 30, (_) => gone, armed: false), isEmpty);
    r.enabled = false;
    expect(run(w, r, 0, 30, (_) => gone), isEmpty);
  });

  test('больше maxPerHour перезапусков в час — сдаётся; через час снова можно', () {
    final w = GuardWatch(), r = rule(max: 1);
    r.restarts.add(at(-600)); // 10 minutes ago
    expect(run(w, r, 0, 5, (_) => gone), ['3 stopAndClose', '3 giveUp']);
    final r2 = rule(max: 1)..restarts.add(at(-3700)); // more than an hour ago
    expect(run(GuardWatch(), r2, 0, 5, (_) => gone), ['3 stopAndClose', '5 launch']);
    expect(r2.restarts, [at(3)], reason: 'старые перезапуски забыты');
  });

  test('без пути запуска — остановить скрипт и сообщить', () {
    final steps = run(GuardWatch(), rule(launch: ''), 0, 5, (_) => gone);
    expect(steps, ['3 stopAndClose', '3 giveUp']);
  });

  test('программа не запустилась за 2 минуты — сдаётся', () {
    final w = GuardWatch(), r = rule();
    final steps = run(w, r, 0, 200, (s) => s < 10 ? ok : gone);
    expect(steps, ['13 stopAndClose', '15 launch', '135 giveUp'], reason: 'после «сдаюсь» молчит');
    // the script is started again by the user: watching again
    run(w, r, 201, 201, (_) => ok, armed: false);
    expect(run(w, r, 202, 210, (_) => gone), ['205 stopAndClose', '207 launch']);
  });

  test('скрипт не запускается поверх другого: ждёт', () {
    final w = GuardWatch(), r = rule();
    final steps = run(w, r, 0, 40, (s) => s < 10 ? ok : (s < 20 ? gone : ok), busy: true);
    expect(steps, ['13 stopAndClose', '15 launch']);
    expect(w.busy(r), isTrue);
    expect(run(w, r, 41, 41, (_) => ok), ['41 runScript']);
  });

  test('сохранение и имя процесса', () {
    final r = rule()..restarts.add(at(1));
    final back = GuardRule.fromJson(r.toJson());
    expect(back.toJson(), r.toJson());
    expect(GuardRule.processName(r'C:\Games\Game.exe'), 'game.exe');
    expect(GuardRule.processName('notepad'), 'notepad.exe');
    expect(r.describe(), contains('Фарм'));
  });
}
