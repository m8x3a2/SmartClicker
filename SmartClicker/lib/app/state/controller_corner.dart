// Emergency stop "move the mouse into a corner of the screen": works when the
// keyboard is taken by a game. Only moves of the user count, not the script's.
part of 'app_controller.dart';

extension AppControllerCorner on AppController {
  /// How long the mouse has to stay in the corner (polls of 25 ms).
  static const holdTicks = 12; // 0.3 s

  /// Name of the screen corner [p] is in (within [margin] px), or null.
  static String? cornerOf(Pt p, ({int w, int h}) screen, {int margin = 2}) {
    final left = p.x <= margin, top = p.y <= margin;
    final right = p.x >= screen.w - 1 - margin, bottom = p.y >= screen.h - 1 - margin;
    if (top && left) return 'левый верхний';
    if (top && right) return 'правый верхний';
    if (bottom && left) return 'левый нижний';
    if (bottom && right) return 'правый нижний';
    return null;
  }

  /// The cursor is in a corner and the USER put it there: their last move
  /// ended in the same corner. A script moving the mouse there does not count.
  static String? userCorner(Pt cursor, ({int x, int y, int ageMs})? user, ({int w, int h}) screen) {
    final c = cornerOf(cursor, screen);
    if (c == null || user == null) return null;
    return cornerOf((x: user.x, y: user.y), screen) == c ? c : null;
  }

  /// The check button in the settings: 10 s to move the mouse into a corner.
  void startCornerTest() {
    _cornerTestUntil = _tick + 400;
    _cornerTicks = 0;
    notify('Проверка: мышь в угол',
        'В течение 10 секунд уведите мышь в любой угол экрана и задержите там на полсекунды');
  }

  void _checkCornerStop() {
    final testing = _cornerTestUntil > _tick;
    if (_cornerTestUntil != 0 && !testing) {
      _cornerTestUntil = 0;
      notify('Угол не замечен', 'За 10 секунд мышь не задержалась в углу экрана. Попробуйте ещё раз',
          level: 'warn');
    }
    // Only a running script stops: during the recording the mouse may
    // well go into a corner (the Start button).
    final active = settings.cornerStop && (isRunning || state == RunState.countdown);
    final want = testing || active;
    if (want != _mouseWatched) {
      _mouseWatched = want;
      backend.watchUserMouse(want);
    }
    if (!want) {
      _cornerTicks = 0;
      return;
    }
    final corner = userCorner(backend.cursorPos(), backend.lastUserMouse(), backend.screenSize());
    if (corner == null) {
      _cornerTicks = 0;
      return;
    }
    if (++_cornerTicks != holdTicks) return; // fires once per visit
    if (testing) {
      _cornerTestUntil = 0;
      notify('Мышь в угол — работает',
          'Замечен $corner угол. ${settings.cornerStop ? 'Работающий скрипт здесь остановится' : 'Включите настройку, чтобы скрипты останавливались'}',
          level: 'ok');
      return;
    }
    _log('system', '⏹ Стоп: мышь в углу экрана ($corner)');
    stop(hotkey: true);
  }
}
