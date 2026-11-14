// Emergency stop "mouse into a corner": which corner, and that only the
// user's own move into it counts (not a script's).
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/app/state/app_controller.dart';
import 'package:smart_clicker/core/storage/storage.dart';

void main() {
  const screen = (w: 1920, h: 1080);

  test('углы экрана', () {
    String? c(int x, int y) => AppControllerCorner.cornerOf((x: x, y: y), screen);
    expect(c(0, 0), 'левый верхний');
    expect(c(2, 1), 'левый верхний');
    expect(c(1919, 0), 'правый верхний');
    expect(c(0, 1079), 'левый нижний');
    expect(c(1919, 1079), 'правый нижний');
    expect(c(0, 500), isNull); // an edge is not a corner
    expect(c(960, 0), isNull);
    expect(c(5, 5), isNull);
  });

  test('считается только мышь, которую в угол увёл человек', () {
    String? u(({int x, int y}) cursor, ({int x, int y, int ageMs})? user) =>
        AppControllerCorner.userCorner(cursor, user, screen);
    // The user moved it there.
    expect(u((x: 0, y: 0), (x: 0, y: 0, ageMs: 50)), 'левый верхний');
    // A script moved it there: the user's last move was elsewhere.
    expect(u((x: 0, y: 0), (x: 700, y: 400, ageMs: 50)), isNull);
    // No move of the user seen yet.
    expect(u((x: 0, y: 0), null), isNull);
    // The user went to another corner, then a script moved the mouse.
    expect(u((x: 0, y: 0), (x: 1919, y: 1079, ageMs: 50)), isNull);
    // Not in a corner at all.
    expect(u((x: 500, y: 500), (x: 500, y: 500, ageMs: 50)), isNull);
  });

  test('по умолчанию выключено, настройка сохраняется, есть скрипт-проверка', () {
    expect(Settings().cornerStop, isFalse);
    expect(Settings.fromJson((Settings()..cornerStop = true).toJson()).cornerStop, isTrue);
    expect(settingsGroups['hotkeys'], contains('cornerStop'));
    expect(checkScripts.keys, contains('03 Мышь в угол'));
  });
}
