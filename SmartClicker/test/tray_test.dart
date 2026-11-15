import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/app/state/app_controller.dart';
import 'package:smart_clicker/core/storage/storage.dart';
import 'package:smart_clicker/app/ui/help/help_screen.dart';
import 'package:smart_clicker/platform/windows/tray_icon.dart';

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

  test('точка на значке в трее: цвет по состоянию', () {
    String mark(RunState s, {bool error = false}) => AppControllerWindow.trayMarkFor(s, error: error);
    expect(mark(RunState.running), 'run');
    expect(mark(RunState.paused), 'pause');
    expect(mark(RunState.countdown), 'pause'); // also waiting for a restart
    expect(mark(RunState.idle), '');
    expect(mark(RunState.idle, error: true), 'error');
    expect(mark(RunState.running, error: true), 'run');
  });

  test('точка рисуется в правом нижнем углу и не трогает остальное', () {
    const size = 16;
    final px = Uint8List(size * size * 4);
    drawStatusDot(px, size, trayMarkColors['error']!);
    int at(int x, int y, int c) => px[(y * size + x) * 4 + c];
    expect(at(0, 0, 3), 0); // top left corner untouched
    expect(at(size ~/ 2, 2, 3), 0);
    // The centre of the dot is opaque red (BGRA).
    const c = size - 5;
    expect([at(c, c, 2), at(c, c, 1), at(c, c, 0), at(c, c, 3)], [0xE0, 0x31, 0x31, 255]);
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
