import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/core/automation/autorun.dart';
import 'package:smart_clicker/platform/backend.dart';

const game = WindowInfo(1, 'Моя игра', 'Game.exe', 10, 0, 0, 800, 600);
const notes = WindowInfo(2, 'Без имени — Блокнот', 'notepad.exe', 11, 0, 0, 400, 300);

void main() {
  test('запуск при старте программы; уже открытая — не считается', () {
    final r = AutoRule(script: 'Ферма', target: 'game');
    final w = AutoWatch();
    List<AutoAction> step(List<WindowInfo> ws, {bool idle = true, AutoRule? owner}) =>
        [for (final a in w.check([r], ws, null, idle: idle, owner: owner)) a.$2];

    // SmartClicker was opened while the game was already running.
    expect(step([game]), isEmpty);
    expect(step([game]), isEmpty);
    // The game closes and starts again.
    expect(step([]), isEmpty);
    expect(step([game]), [AutoAction.start]);
    // Running: nothing more; the game closes -> stop.
    expect(step([game], idle: false, owner: r), isEmpty);
    expect(step([], idle: false, owner: r), [AutoAction.stop]);
    // Busy with another script: the start waits until it is idle.
    expect(step([game], idle: false), isEmpty);
    expect(step([game]), [AutoAction.start]);
  });

  test('окно стало активным: запуск, пауза и продолжение', () {
    final r = AutoRule(script: 'Ферма', target: 'Game.exe|игра', trigger: 'focus', leave: 'pause');
    final w = AutoWatch();
    List<AutoAction> step(WindowInfo? active,
            {bool idle = true, AutoRule? owner, bool paused = false}) =>
        [
          for (final a in w.check([r], [game, notes], active,
              idle: idle, owner: owner, ownerPaused: paused))
            a.$2
        ];

    expect(step(notes), isEmpty);
    expect(step(game), [AutoAction.start]);
    expect(step(game, idle: false, owner: r), isEmpty);
    expect(step(notes, idle: false, owner: r), [AutoAction.pause]);
    expect(step(notes, idle: false, owner: r, paused: true), isEmpty);
    expect(step(game, idle: false, owner: r, paused: true), [AutoAction.resume]);
    // The script finished by itself while the window is active: no restart.
    expect(step(game), isEmpty);
    // Switched away and back: starts again.
    expect(step(notes), isEmpty);
    expect(step(game), [AutoAction.start]);
  });

  test('выключенное правило молчит, за раз запускается один скрипт', () {
    final a = AutoRule(script: 'A', target: 'notepad', trigger: 'focus');
    final b = AutoRule(script: 'B', target: 'Блокнот', trigger: 'focus');
    final off = AutoRule(script: 'C', target: 'notepad', trigger: 'focus', enabled: false);
    final w = AutoWatch();
    final got = w.check([off, a, b], [notes], notes, idle: true);
    expect(got.map((e) => e.$1.script), ['A']);
  });

  test('правило сохраняется и описывается', () {
    final r = AutoRule.fromJson(AutoRule(
            script: 'Папка/Ферма', target: 'game', trigger: 'focus', leave: 'pause')
        .toJson());
    expect([r.script, r.target, r.trigger, r.leave, r.enabled],
        ['Папка/Ферма', 'game', 'focus', 'pause', true]);
    expect(r.describe(), contains('становится активным'));
    // A pause makes no sense for "program started": becomes a stop.
    expect(AutoRule.fromJson({'script': 's', 'target': 't', 'leave': 'pause'}).leave, 'stop');
  });
}
