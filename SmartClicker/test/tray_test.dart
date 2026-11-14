import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/app/state/app_controller.dart';
import 'package:smart_clicker/core/storage/storage.dart';
import 'package:smart_clicker/app/ui/help/help_screen.dart';

void main() {
  test('меню значка в трее зависит от состояния', () {
    var m = AppController.trayMenuFor(RunState.idle, 'Ферма', null);
    expect(m.items, ['Открыть SmartClicker', '', 'Запустить «Ферма»', '', 'Выход']);
    expect(m.actions, ['open', '', 'run', '', 'quit']);
    expect(m.items.length, m.actions.length);

    m = AppController.trayMenuFor(RunState.idle, null, null);
    expect(m.items[2], startsWith('!')); // greyed out

    m = AppController.trayMenuFor(RunState.running, 'Ферма', 'Ферма', stopKey: 'f12');
    expect(m.items, contains('Пауза'));
    expect(m.items, contains('Остановить «Ферма» (F12)'));
    expect(m.actions, containsAll(['pause', 'stop', 'quit']));

    m = AppController.trayMenuFor(RunState.paused, 'Ферма', 'Ферма');
    expect(m.items, contains('Продолжить'));

    m = AppController.trayMenuFor(RunState.recording, 'Ферма', null);
    expect(m.items, contains('Остановить запись'));
  });

  test('настройки трея сохраняются', () {
    expect(Settings().trayOnMinimize, isTrue);
    expect(Settings().trayOnClose, isFalse);
    final s = Settings.fromJson((Settings()
          ..trayOnMinimize = false
          ..trayOnClose = true)
        .toJson());
    expect([s.trayOnMinimize, s.trayOnClose], [false, true]);
  });

  test('раздел «Возможности» — первый в справке', () {
    expect(helpSections.first.title, 'Возможности');
    expect(helpSections.first.text, contains('ЗРЕНИЕ'));
  });
}
