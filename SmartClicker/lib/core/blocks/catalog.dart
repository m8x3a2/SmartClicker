// Catalogue of blocks: a phrase and parameters for every built-in function,
// categories and the palette.

import '../lang/completions.dart';
import 'blocks.dart';

/// Kind of a parameter: decides the helper next to the slot (point
/// picker, list of pictures, key capture...).
enum PK { coord, size, number, ms, text, color, key, picture, window, process, script, bool, choice, any }

class PSpec {
  final String name;

  /// Short word shown before the slot when it is not part of the label.
  final String label;
  final String hint;
  final PK kind;

  /// Expression put into the slot when the parameter is added.
  final String def;

  /// For [PK.choice]: value (as code) → explanation.
  final Map<String, String> options;

  /// May be left out (only trailing positional parameters).
  final bool optional;

  /// Takes any number of values (log).
  final bool rest;
  const PSpec(this.name, this.hint,
      {this.kind = PK.any,
      this.def = 'null',
      this.label = '',
      this.options = const {},
      this.optional = false,
      this.rest = false});
}

class BCat {
  final String id;
  final String title;
  final int color;

  /// Name in the narrow column of categories.
  final String short;
  const BCat(this.id, this.title, this.color, this.short);
}

const blockCats = <BCat>[
  BCat('control', 'Управление', 0xFFC7870F, 'Управление'),
  BCat('mouse', 'Мышь', 0xFF3B78D8, 'Мышь'),
  BCat('keys', 'Клавиатура', 0xFF7D55D9, 'Клавиши'),
  BCat('wait', 'Ожидание и время', 0xFF0F949A, 'Ожидание'),
  BCat('screen', 'Экран и картинки', 0xFF2E9455, 'Экран'),
  BCat('windows', 'Окна и программы', 0xFFBA4479, 'Окна'),
  BCat('vars', 'Переменные и лог', 0xFFD45A26, 'Перемен.'),
  BCat('ops', 'Операторы и числа', 0xFF5E9420, 'Операторы'),
  BCat('system', 'Система и файлы', 0xFF5F6D8A, 'Система'),
  BCat('funcs', 'Мои функции', 0xFF9B42BC, 'Функции'),
  BCat('other', 'Комментарии и код', 0xFF596070, 'Заметки'),
];

BCat catById(String id) =>
    blockCats.firstWhere((c) => c.id == id, orElse: () => blockCats.last);

/// A built-in function as a block.
class FSpec {
  final String name;
  final String cat;

  /// Words of the block; `{param}` marks where a slot goes.
  final String label;
  final List<PSpec> params;

  /// Named parameters that make sense for this function (see [namedParams]).
  final List<String> named;

  /// What the function gives back (null — nothing useful).
  final String? returns;

  /// Name of the variable when a value block is dropped among statements.
  final String saveAs;

  /// Code of the palette item.
  final String example;

  /// Offered as a statement; otherwise only as a value for slots.
  final bool statement;

  /// Own explanation; by default the one of the code editor.
  final String about;
  const FSpec(this.name, this.cat, this.label, this.params, this.example,
      {this.named = const [],
      this.returns,
      this.saveAs = 'result',
      this.statement = true,
      this.about = ''});

  /// Explanation shown under the mouse (the same as in the code editor).
  String get hint => about.isNotEmpty ? about : (completionFor(name)?.hint ?? '');
  String get signature => completionFor(name)?.signature ?? '$name(...)';
  bool get isValue => returns != null;

  PSpec? param(String name) {
    for (final p in params) {
      if (p.name == name) return p;
    }
    return null;
  }
}

// ---------------------------------------------------------------- parameters

const _hx = 'X — по горизонтали: пиксели (960) или проценты (50%). Прицел справа — взять точку кликом';
const _hy = 'Y — по вертикали: пиксели (540) или проценты (50%)';
const _hw = 'ширина области: пиксели или проценты';
const _hh = 'высота области: пиксели или проценты';
const _hColor = 'цвет "#RRGGBB"; взять можно клавишей F6 или прицелом';
const _hPicture = 'имя картинки из папки files (без .png); картинку вырезают в разделе «Картинки»';
const _hWindow = 'окно: часть заголовка, "программа.exe" или "программа|заголовок"';
const _hKey = 'клавиша или сочетание: "enter", "ctrl+c", "alt+tab", "f5"';
const _hMs = 'время: 500 (мс), 1s, 2m или случайно 800..1200';
const _hText = 'текст в кавычках или переменная';

const _x = PSpec('x', _hx, kind: PK.coord, def: '50%');
const _y = PSpec('y', _hy, kind: PK.coord, def: '50%');
const _xo = PSpec('x', '$_hx. Без точки — там, где сейчас курсор', kind: PK.coord, def: '50%', optional: true);
const _yo = PSpec('y', _hy, kind: PK.coord, def: '50%', optional: true);
const _w = PSpec('w', _hw, kind: PK.size, def: '20%');
const _h = PSpec('h', _hh, kind: PK.size, def: '10%');
const _ax = PSpec('x', 'левый край области: пиксели или проценты. Прицел — выделить область двумя нажатиями Ctrl',
    kind: PK.coord, def: '0', label: 'в области', optional: true);
const _ay = PSpec('y', 'верхний край области', kind: PK.coord, def: '0', optional: true);
const _aw = PSpec('w', _hw, kind: PK.size, def: '100%', optional: true);
const _ah = PSpec('h', _hh, kind: PK.size, def: '100%', optional: true);
const _rx = PSpec('x', 'левый край области: пиксели или проценты. Прицел — выделить область двумя нажатиями Ctrl',
    kind: PK.coord, def: '40%');
const _ry = PSpec('y', 'верхний край области', kind: PK.coord, def: '40%');
const _picture = PSpec('name', _hPicture, kind: PK.picture, def: '"кнопка"');
const _window = PSpec('window', _hWindow, kind: PK.window, def: '"Блокнот"');
const _process = PSpec('process', 'программа: "game.exe"', kind: PK.process, def: '"notepad.exe"');
const _color = PSpec('color', _hColor, kind: PK.color, def: '"#FF0000"');
const _value = PSpec('value', 'значение: число, текст, переменная', def: '0');

/// Named parameters: how they look as slots.
final namedParams = <String, PSpec>{
  'timeout': PSpec('timeout', paramHints['timeout']!, kind: PK.ms, def: '5s', label: 'не дольше'),
  'tolerance':
      PSpec('tolerance', paramHints['tolerance']!, kind: PK.number, def: '20', label: 'допуск'),
  'engine': PSpec('engine', paramHints['engine']!,
      kind: PK.choice,
      def: '"paddle"',
      label: 'распознавание',
      options: const {'"paddle"': 'точное (PaddleOCR)', '"windows"': 'быстрое (Windows)'}),
  'lang': PSpec('lang', paramHints['lang']!, kind: PK.text, def: '"ru"', label: 'язык'),
  'scale': PSpec('scale', paramHints['scale']!, def: '"auto"', label: 'масштаб'),
  'interval':
      PSpec('interval', paramHints['interval']!, kind: PK.ms, def: '500', label: 'проверять раз в'),
  'button': PSpec('button', paramHints['button']!,
      kind: PK.choice,
      def: '"right"',
      label: 'кнопка',
      options: const {'"left"': 'левая', '"right"': 'правая', '"middle"': 'колесо'}),
  'count': PSpec('count', paramHints['count']!, kind: PK.number, def: '2', label: 'раз'),
  'offset': PSpec('offset', paramHints['offset']!, kind: PK.number, def: '10', label: 'разброс ±'),
  'hold': PSpec('hold', paramHints['hold']!, kind: PK.ms, def: '100', label: 'держать'),
  'duration':
      PSpec('duration', paramHints['duration']!, kind: PK.ms, def: '300', label: 'плавно за'),
  'delay': PSpec('delay', paramHints['delay']!, kind: PK.ms, def: '50', label: 'пауза между буквами'),
  'unit': PSpec('unit', paramHints['unit']!,
      kind: PK.choice, def: '"%"', label: 'единицы', options: const {'"%"': 'проценты'}),
  'speed': PSpec('speed', paramHints['speed']!, kind: PK.number, def: '2', label: 'скорость'),
  'focus': PSpec('focus', paramHints['focus']!,
      kind: PK.bool, def: 'false', label: 'выводить вперёд'),
  'new': PSpec('new', paramHints['new']!, kind: PK.bool, def: 'true', label: 'новая копия'),
  'wait': PSpec('wait', paramHints['wait']!, kind: PK.bool, def: 'false', label: 'ждать конца'),
  'options': PSpec('options', paramHints['options']!, def: '["быстро", "медленно"]', label: 'варианты'),
  'horizontal': PSpec('horizontal', paramHints['horizontal']!,
      kind: PK.bool, def: 'true', label: 'вбок'),
};

PSpec namedSpec(String name) =>
    namedParams[name] ??
    PSpec(name, paramHints[name] ?? 'именованный параметр $name', label: name);

const _click = ['offset', 'hold', 'duration'];
const _ocr = ['engine', 'lang', 'scale'];
const _image = ['tolerance', 'scale'];

// ------------------------------------------------------------------ functions

const functionSpecs = <FSpec>[
  // Mouse
  FSpec('click', 'mouse', 'кликнуть {x} {y}', [_xo, _yo], 'click(50%, 50%)',
      named: ['button', 'count', ..._click]),
  FSpec('double_click', 'mouse', 'двойной клик {x} {y}', [_xo, _yo], 'double_click(50%, 50%)',
      named: _click),
  FSpec('right_click', 'mouse', 'правый клик {x} {y}', [_xo, _yo], 'right_click(50%, 50%)',
      named: ['count', ..._click]),
  FSpec('middle_click', 'mouse', 'клик колесом {x} {y}', [_xo, _yo], 'middle_click(50%, 50%)',
      named: ['count', ..._click]),
  FSpec('move', 'mouse', 'навести курсор на {x} {y}', [_x, _y], 'move(50%, 50%)',
      named: ['duration', 'offset']),
  FSpec('drag', 'mouse', 'перетащить от {x1} {y1} до {x2} {y2}', [
    PSpec('x1', 'откуда: X', kind: PK.coord, def: '40%'),
    PSpec('y1', 'откуда: Y', kind: PK.coord, def: '50%'),
    PSpec('x2', 'куда: X', kind: PK.coord, def: '60%'),
    PSpec('y2', 'куда: Y', kind: PK.coord, def: '50%'),
    PSpec('duration', 'за сколько провести, мс (по умолчанию 400)',
        kind: PK.ms, def: '400', label: 'за', optional: true),
  ], 'drag(40%, 50%, 60%, 50%)', named: ['button']),
  FSpec('hold', 'mouse', 'зажать мышь в {x} {y}', [
    _x,
    _y,
    PSpec('duration', 'сколько держать (по умолчанию 1000 мс)',
        kind: PK.ms, def: '1500', label: 'на', optional: true),
  ], 'hold(50%, 50%, 1500)', named: ['button']),
  FSpec('scroll', 'mouse', 'прокрутить колесо на {amount}', [
    PSpec('amount', 'на сколько щелчков: 3 — вниз, -3 — вверх', kind: PK.number, def: '3'),
    PSpec('x', 'где крутить: X (без точки — где курсор)',
        kind: PK.coord, def: '50%', label: 'в точке', optional: true),
    PSpec('y', 'где крутить: Y', kind: PK.coord, def: '50%', optional: true),
  ], 'scroll(3)', named: ['horizontal']),
  FSpec('mouse_down', 'mouse', 'зажать кнопку мыши {x} {y}', [_xo, _yo], 'mouse_down()',
      named: ['button', 'duration']),
  FSpec('mouse_up', 'mouse', 'отпустить кнопку мыши {x} {y}', [_xo, _yo], 'mouse_up()',
      named: ['button', 'duration']),
  FSpec('mouse_path', 'mouse', 'провести курсор по траектории {points}', [
    PSpec('points', 'точки "x,y,мс x,y,мс …" — так её пишет запись в режиме «полная траектория»',
        kind: PK.text, def: '"100,100,0 400,300,200"'),
  ], 'mouse_path("100,100,0 400,300,200")', named: ['unit', 'speed']),
  FSpec('mouse_pos', 'mouse', 'позиция курсора', [], 'mouse_pos()',
      returns: '{x, y, px, py} — пиксели и проценты', saveAs: 'pos', statement: false),

  // Keyboard
  FSpec('key', 'keys', 'нажать клавишу {key}',
      [PSpec('key', _hKey, kind: PK.key, def: '"enter"')], 'key("enter")',
      named: ['count', 'hold']),
  FSpec('key_down', 'keys', 'зажать клавишу {key}',
      [PSpec('key', _hKey, kind: PK.key, def: '"shift"')], 'key_down("shift")'),
  FSpec('key_up', 'keys', 'отпустить клавишу {key}',
      [PSpec('key', _hKey, kind: PK.key, def: '"shift"')], 'key_up("shift")'),
  FSpec('type', 'keys', 'напечатать {text}',
      [PSpec('text', 'что напечатать (любой язык)', kind: PK.text, def: '"Привет"')],
      'type("Привет")', named: ['delay']),
  FSpec('paste', 'keys', 'вставить текст {text}',
      [PSpec('text', 'текст вставляется через буфер обмена (Ctrl+V) — быстро и без раскладки',
          kind: PK.text, def: '"Привет"')],
      'paste("Привет")'),

  // Waiting and time
  FSpec('wait', 'wait', 'ждать {ms}', [PSpec('ms', _hMs, kind: PK.ms, def: '1s')], 'wait(1s)'),
  FSpec('wait_until', 'wait', 'ждать до {time}',
      [PSpec('time', 'время "чч:мм" или "чч:мм:сс"', kind: PK.text, def: '"14:30"')],
      'wait_until("14:30")'),
  FSpec('wait_pixel', 'wait', 'ждать цвет {color} в точке {x} {y}', [_x, _y, _color],
      'wait_pixel(50%, 50%, "#FF0000", timeout: 10s)',
      named: ['timeout', 'tolerance', 'interval'],
      returns: 'true — дождались, false — время вышло'),
  FSpec('wait_text', 'wait', 'ждать текст {text} в области {x} {y} {w} {h}', [
    _rx, _ry, _w, _h,
    PSpec('text', 'какой текст ждать (регистр и лишние пробелы не важны)',
        kind: PK.text, def: '"Готово"'),
  ], 'wait_text(40%, 40%, 20%, 10%, "Готово", timeout: 10s)',
      named: ['timeout', 'interval', ..._ocr], returns: 'true — дождались, false — время вышло'),
  FSpec('wait_image', 'wait', 'ждать картинку {name}', [_picture, _ax, _ay, _aw, _ah],
      'wait_image("кнопка", timeout: 10s)',
      named: ['timeout', 'interval', ..._image],
      returns: '{x, y} — где появилась, или null', saveAs: 'pos'),
  FSpec('now', 'wait', 'сейчас, мс', [], 'now()',
      returns: 'миллисекунды — для замеров: let t = now() … now() - t', saveAs: 'start', statement: false),
  FSpec('elapsed', 'wait', 'сколько работает скрипт, мс', [], 'elapsed()',
      returns: 'миллисекунды с запуска', saveAs: 'ms', statement: false),
  FSpec('time', 'wait', 'время «чч:мм:сс»', [], 'time()',
      returns: 'строка "14:30:05"', saveAs: 't', statement: false),
  FSpec('date', 'wait', 'дата «гггг-мм-дд»', [], 'date()',
      returns: 'строка "2026-01-31"', saveAs: 'd', statement: false),
  FSpec('clock', 'wait', 'часы и дата', [], 'clock()',
      returns: '{year, month, day, weekday, hour, minute, second}', saveAs: 'c', statement: false),

  // Screen and pictures
  FSpec('pixel', 'screen', 'цвет точки {x} {y}', [_x, _y], 'pixel(50%, 50%)',
      returns: 'цвет "#RRGGBB"', saveAs: 'color', statement: false),
  FSpec('pixel_is', 'screen', 'цвет точки {x} {y} — {color}', [_x, _y, _color],
      'pixel_is(50%, 50%, "#FFFFFF")',
      named: ['tolerance'], returns: 'true / false', saveAs: 'ok', statement: false),
  FSpec('avg_color', 'screen', 'средний цвет области {x} {y} {w} {h}', [_rx, _ry, _w, _h],
      'avg_color(40%, 40%, 20%, 10%)', returns: 'цвет "#RRGGBB"', saveAs: 'color', statement: false),
  FSpec('find_color', 'screen', 'найти цвет {color}', [_color, _ax, _ay, _aw, _ah],
      'find_color("#FF0000")',
      named: ['tolerance'], returns: '{x, y} или null', saveAs: 'pos', statement: false),
  FSpec('read_text', 'screen', 'текст в области {x} {y} {w} {h}', [_rx, _ry, _w, _h],
      'read_text(40%, 40%, 20%, 10%)',
      named: _ocr, returns: 'прочитанный текст (строки через перенос)', saveAs: 'text', statement: false),
  FSpec('text_in', 'screen', 'в области {x} {y} {w} {h} есть текст {text}', [
    _rx, _ry, _w, _h,
    PSpec('text', 'какой текст искать (регистр и лишние пробелы не важны)',
        kind: PK.text, def: '"Готово"'),
  ], 'text_in(40%, 40%, 20%, 10%, "Готово")',
      named: _ocr, returns: 'true / false', saveAs: 'found', statement: false),
  FSpec('read_number', 'screen', 'число в области {x} {y} {w} {h}', [_rx, _ry, _w, _h],
      'read_number(40%, 40%, 20%, 10%)',
      named: _ocr, returns: 'число или null', saveAs: 'n', statement: false),
  FSpec('find_image', 'screen', 'найти картинку {name}', [_picture, _ax, _ay, _aw, _ah],
      'find_image("кнопка")',
      named: _image, returns: '{x, y} центра картинки или null', saveAs: 'pos', statement: false),
  FSpec('click_image', 'screen', 'кликнуть по картинке {name}', [_picture, _ax, _ay, _aw, _ah],
      'click_image("кнопка")',
      named: ['timeout', 'interval', ..._image, 'button', 'count', 'offset'],
      returns: 'true — кликнули, false — картинки нет', saveAs: 'clicked'),
  FSpec('screenshot', 'screen', 'снимок экрана в картинку {name}',
      [PSpec('name', 'имя файла в папке files (без .png)', kind: PK.text, def: '"снимок"'), _ax, _ay, _aw, _ah],
      'screenshot("снимок")'),
  FSpec('color_diff', 'screen', 'разница цветов {a} и {b}', [
    PSpec('a', _hColor, kind: PK.color, def: '"#FF0000"'),
    PSpec('b', _hColor, kind: PK.color, def: '"#F00000"'),
  ], 'color_diff("#FF0000", "#F00000")',
      returns: 'число 0..255: 0 — одинаковые', saveAs: 'diff', statement: false),
  FSpec('screen_size', 'screen', 'размер экрана', [], 'screen_size()',
      returns: '{w, h} в пикселях', saveAs: 'screen', statement: false),

  // Windows and programs
  FSpec('focus_window', 'windows', 'переключиться на окно {window}', [_window],
      'focus_window("Блокнот")', returns: 'true — окно найдено'),
  FSpec('use_window', 'windows', 'считать координаты от окна {window}', [_window],
      'use_window("Блокнот")'),
  FSpec('use_screen', 'windows', 'считать координаты от экрана', [], 'use_screen()'),
  FSpec('require_window', 'windows', 'нажимать только в окне {window}', [
    PSpec('window', '$_hWindow. null — снять ограничение', kind: PK.window, def: '"Блокнот"'),
  ], 'require_window("Блокнот")', named: ['focus']),
  FSpec('set_window_bounds', 'windows', 'окно {window}: место {x} {y}, размер {w} {h}', [
    _window,
    PSpec('x', 'левый край окна, пиксели', kind: PK.number, def: '0'),
    PSpec('y', 'верхний край окна, пиксели', kind: PK.number, def: '0'),
    PSpec('w', 'ширина окна, пиксели', kind: PK.number, def: '1280'),
    PSpec('h', 'высота окна, пиксели', kind: PK.number, def: '720'),
  ], 'set_window_bounds("Блокнот", 0, 0, 1280, 720)'),
  FSpec('window_exists', 'windows', 'окно {window} открыто', [_window],
      'window_exists("Блокнот")', returns: 'true / false', saveAs: 'open', statement: false),
  FSpec('is_window_active', 'windows', 'окно {window} активно', [_window],
      'is_window_active("Блокнот")', returns: 'true / false', saveAs: 'active', statement: false),
  FSpec('active_window', 'windows', 'активное окно', [], 'active_window()',
      returns: '{title, process, pid, x, y, w, h}', saveAs: 'win', statement: false),
  FSpec('windows', 'windows', 'список окон', [], 'windows()',
      returns: 'массив окон {title, process, …}', saveAs: 'list', statement: false),
  FSpec('launch', 'windows', 'запустить {path}', [
    PSpec('path', 'программа, файл или ссылка: "notepad.exe", "C:\\\\Games\\\\game.exe"',
        kind: PK.text, def: '"notepad.exe"'),
  ], 'launch("notepad.exe")', named: ['new']),
  FSpec('is_process_running', 'windows', 'программа {process} запущена', [_process],
      'is_process_running("notepad.exe")', returns: 'true / false', saveAs: 'running', statement: false),
  FSpec('kill_process', 'windows', 'закрыть программу {process}', [_process],
      'kill_process("notepad.exe")'),
  FSpec('run_command', 'windows', 'выполнить команду {command}', [
    PSpec('command', 'команда, как в командной строке', kind: PK.text, def: '"ipconfig"'),
  ], 'run_command("ipconfig")', named: ['wait'], returns: '{code, out, err}', saveAs: 'res'),

  // Variables and log
  FSpec('log', 'vars', 'в лог {values}', [
    PSpec('values', 'что написать: текст, числа, переменные — через запятую',
        kind: PK.text, def: '"текст"', rest: true),
  ], 'log("Готово")'),
  FSpec('warn', 'vars', 'предупреждение в лог {text}',
      [PSpec('text', _hText, kind: PK.text, def: '"Внимание"')], 'warn("Внимание")'),
  FSpec('notify', 'vars', 'плашка {title} {text}', [
    PSpec('title', 'заголовок плашки', kind: PK.text, def: '"SmartClicker"'),
    PSpec('text', 'текст плашки', kind: PK.text, def: '"Готово"', optional: true),
  ], 'notify("SmartClicker", "Готово")'),
  FSpec('ask', 'vars', 'спросить при запуске {text} {default}', [
    PSpec('text', 'вопрос, который покажется при нажатии «Запуск» (пишите как есть, без вычислений)',
        kind: PK.text, def: '"Сколько раз?"'),
    PSpec('default', 'ответ по умолчанию: число — поле для числа, текст — для текста, '
        'true/false — флажок. Последний ответ запоминается',
        def: '10', label: 'по умолчанию', optional: true),
  ], 'ask("Сколько раз?", 10)', named: ['options'], returns: 'ответ', saveAs: 'answer', statement: false),
  FSpec('save_data', 'vars', 'запомнить {key} = {value}', [
    PSpec('key', 'под каким именем', kind: PK.text, def: '"счёт"'),
    _value,
  ], 'save_data("счёт", 0)'),
  FSpec('load_data', 'vars', 'вспомнить {key}', [
    PSpec('key', 'имя, под которым запомнили', kind: PK.text, def: '"счёт"'),
    PSpec('default', 'что вернуть, если ещё не запоминали',
        def: '0', label: 'если нет —', optional: true),
  ], 'load_data("счёт", 0)', returns: 'запомненное значение', saveAs: 'saved', statement: false),

  // Control
  FSpec('exit', 'control', 'завершить скрипт', [], 'exit()'),
  FSpec('run_script', 'control', 'выполнить скрипт {name}', [
    PSpec('name', 'имя скрипта, как в списке слева ("Папка/Имя")', kind: PK.script, def: '"Имя"'),
  ], 'run_script("Имя")'),
  FSpec('set_option', 'control', 'настройка {name} = {value}', [
    PSpec('name', 'какая настройка', kind: PK.choice, def: '"human"', options: {
      '"human"': 'человеческие движения (true/false)',
      '"click_offset"': 'разброс клика, px',
      '"time_jitter"': 'разброс пауз, например 10%',
    }),
    PSpec('value', 'новое значение', def: 'true'),
  ], 'set_option("human", true)'),

  // Operators and numbers
  FSpec('random', 'ops', 'случайное от {a} до {b}', [
    PSpec('a', 'от', kind: PK.number, def: '1'),
    PSpec('b', 'до', kind: PK.number, def: '10'),
  ], 'random(1, 10)', returns: 'дробное число', saveAs: 'r', statement: false),
  FSpec('random_int', 'ops', 'случайное целое от {a} до {b}', [
    PSpec('a', 'от', kind: PK.number, def: '1'),
    PSpec('b', 'до (включительно)', kind: PK.number, def: '10'),
  ], 'random_int(1, 10)', returns: 'целое число', saveAs: 'r', statement: false),
  FSpec('chance', 'ops', 'с вероятностью {p}',
      [PSpec('p', 'вероятность: 30% или 0.3', kind: PK.number, def: '30%')], 'chance(30%)',
      returns: 'true с этой вероятностью', saveAs: 'lucky', statement: false),
  FSpec('pick', 'ops', 'случайный из {list}',
      [PSpec('list', 'массив: [1, 2, 3] или ["a", "b"]', def: '[1, 2, 3]')], 'pick([1, 2, 3])',
      returns: 'случайный элемент', saveAs: 'item', statement: false),
  FSpec('len', 'ops', 'длина {x}', [PSpec('x', 'строка или массив', def: '"текст"')], 'len("текст")',
      returns: 'число', saveAs: 'n', statement: false),
  FSpec('str', 'ops', 'текст из {value}', [_value], 'str(5)', returns: 'строка', saveAs: 's', statement: false),
  FSpec('int', 'ops', 'целое из {value}', [_value], 'int("5")', returns: 'целое число', saveAs: 'n', statement: false),
  FSpec('float', 'ops', 'дробное из {value}', [_value], 'float("1.5")',
      returns: 'дробное число', saveAs: 'n', statement: false),
  FSpec('type_of', 'ops', 'тип {value}', [_value], 'type_of(5)',
      returns: '"number", "string", "array"…', saveAs: 't', statement: false),
  FSpec('keys', 'ops', 'ключи объекта {o}', [PSpec('o', 'объект', def: '{a: 1}')], 'keys({a: 1})',
      returns: 'массив ключей', saveAs: 'k', statement: false),
  FSpec('to_json', 'ops', 'в JSON {value}', [_value], 'to_json([1, 2])',
      returns: 'строка JSON', saveAs: 'json', statement: false),
  FSpec('from_json', 'ops', 'из JSON {s}', [PSpec('s', 'строка JSON', kind: PK.text, def: '"[1, 2]"')],
      'from_json("[1, 2]")', returns: 'значение', saveAs: 'data', statement: false),

  // System and files
  FSpec('battery_level', 'system', 'заряд батареи', [], 'battery_level()',
      returns: '0..100 или null (нет батареи)', saveAs: 'battery', statement: false),
  FSpec('is_charging', 'system', 'идёт зарядка', [], 'is_charging()',
      returns: 'true / false', saveAs: 'charging', statement: false),
  FSpec('is_network_connected', 'system', 'есть сеть', [], 'is_network_connected()',
      returns: 'true / false', saveAs: 'online', statement: false),
  FSpec('cpu_usage', 'system', 'загрузка процессора {process}', [
    PSpec('process', 'программа ("game.exe") — сколько берёт она; без неё — весь компьютер',
        kind: PK.process, def: '"notepad.exe"', optional: true),
  ], 'cpu_usage()', named: ['interval'], returns: 'проценты', saveAs: 'cpu', statement: false),
  FSpec('ram_usage', 'system', 'занято памяти {process}', [
    PSpec('process', 'программа — её память в МБ; без неё — % всей памяти',
        kind: PK.process, def: '"notepad.exe"', optional: true),
  ], 'ram_usage()', returns: '% или МБ', saveAs: 'ram', statement: false),
  FSpec('ram_info', 'system', 'память компьютера', [], 'ram_info()',
      returns: '{total, free, used} в МБ', saveAs: 'mem', statement: false),
  FSpec('system_power', 'system', 'компьютер: {action}', [
    PSpec('action', 'что сделать', kind: PK.choice, def: '"lock"', options: {
      '"lock"': 'заблокировать',
      '"sleep"': 'сон',
      '"hibernate"': 'гибернация',
      '"shutdown"': 'выключить',
      '"restart"': 'перезагрузить',
      '"logoff"': 'выйти из системы',
    }),
  ], 'system_power("lock")'),
  FSpec('get_clipboard', 'system', 'текст из буфера обмена', [], 'get_clipboard()',
      returns: 'строка', saveAs: 'clip', statement: false),
  FSpec('set_clipboard', 'system', 'положить в буфер обмена {text}',
      [PSpec('text', _hText, kind: PK.text, def: '"текст"')], 'set_clipboard("текст")'),
  FSpec('read_file', 'system', 'прочитать файл {path}',
      [PSpec('path', 'имя файла (в папке files) или полный путь', kind: PK.text, def: '"a.txt"')],
      'read_file("a.txt")', returns: 'текст файла', saveAs: 'text', statement: false),
  FSpec('write_file', 'system', 'записать в файл {path} текст {text}', [
    PSpec('path', 'имя файла (в папке files) или полный путь', kind: PK.text, def: '"a.txt"'),
    PSpec('text', _hText, kind: PK.text, def: '"текст"'),
  ], 'write_file("a.txt", "текст")'),
  FSpec('append_file', 'system', 'дописать в файл {path} текст {text}', [
    PSpec('path', 'имя файла (в папке files) или полный путь', kind: PK.text, def: '"a.txt"'),
    PSpec('text', _hText, kind: PK.text, def: '"текст"'),
  ], 'append_file("a.txt", "текст")'),
  FSpec('file_exists', 'system', 'файл {path} есть',
      [PSpec('path', 'имя файла (в папке files) или полный путь', kind: PK.text, def: '"a.txt"')],
      'file_exists("a.txt")', returns: 'true / false', saveAs: 'exists', statement: false),
];

final Map<String, FSpec> _byName = {for (final f in functionSpecs) f.name: f};

final _camelHump = RegExp('[A-Z]');

/// Spec of a built-in function; camelCase names are understood too.
FSpec? specFor(String name) =>
    _byName[name] ??
    _byName[name.replaceAllMapped(_camelHump, (m) => '_${m[0]!.toLowerCase()}')];

// -------------------------------------------------------------- statements

/// Explanations of the block kinds that are not function calls.
const kindHints = <String, String>{
  BK.ifs: 'Если условие верно — выполнить блоки внутри. «Иначе если» проверяется, когда '
      'предыдущие условия неверны; «иначе» — когда неверны все.',
  BK.repeat: 'Повторить блоки внутри указанное число раз. Без числа — бесконечно, до '
      'остановки (F12) или «выйти из цикла».',
  BK.withWin: 'Блоки внутри работают с этим окном: координаты считаются от него, клики и '
      'клавиши идут только в него (если окно перекрыли — оно выводится вперёд). После блока '
      'всё как было — use_screen() писать не нужно.',
  BK.whiles: 'Повторять, пока условие верно. Условие проверяется перед каждым кругом. '
      'Не забудьте паузу внутри — иначе цикл займёт процессор.',
  BK.doWhile: 'Сначала выполнить блоки, потом повторять, пока условие верно.',
  BK.forIn: 'Для каждого значения: 1..10 — числа от 1 до 10, массив — каждый его элемент. '
      'Текущее значение лежит в переменной.',
  BK.forC: 'Цикл в стиле C: начало; условие; шаг.',
  BK.func: 'Своя команда: блоки внутри выполняются, когда её вызывают по имени '
      '(блок появится в «Моих функциях»). Параметры — через запятую.',
  BK.ret: 'Выйти из функции; можно вернуть значение.',
  BK.brk: 'Выйти из цикла (дальше выполняется то, что после цикла).',
  BK.cont: 'Сразу перейти к следующему кругу цикла.',
  BK.thr: 'Остановить скрипт с ошибкой (или передать её в «при ошибке»).',
  BK.tryc: 'Выполнить блоки; если случится ошибка — не останавливаться, а выполнить блоки '
      '«при ошибке» (в переменной — её текст). «В конце» выполняется всегда.',
  BK.sw: 'Выбор по значению: выполняется вариант, равный значению; «иначе» — если ни один '
      'не подошёл. Не забудьте «выйти» (break) в конце варианта.',
  BK.let: 'Создать переменную и положить в неё значение.',
  BK.set: 'Поменять значение переменной: = — заменить, += — прибавить, -= — отнять.',
  BK.comment: 'Комментарий — заметка для себя, не выполняется. В коде начинается с //.',
  BK.code: 'Код как есть — для того, чего нет среди блоков. Можно вписать любые команды: '
      'если они знакомы конструктору, станут блоками.',
};

/// A block in the palette.
class PaletteItem {
  final String cat;
  final String code;

  /// A value (goes into slots); otherwise a statement.
  final bool value;

  /// Search words besides the label (code is searched too).
  final String words;
  const PaletteItem(this.cat, this.code, {this.value = false, this.words = ''});
}

const _controlItems = <PaletteItem>[
  PaletteItem('control', 'repeat (10) {\n}', words: 'повторить цикл раз'),
  PaletteItem('control', 'repeat {\n}', words: 'повторять всегда бесконечно цикл'),
  PaletteItem('control', 'if (true) {\n}', words: 'если условие'),
  PaletteItem('control', 'if (true) {\n} else {\n}', words: 'если иначе условие'),
  PaletteItem('control', 'while (true) {\n}', words: 'пока цикл'),
  PaletteItem('control', 'for (i in 1..10) {\n}', words: 'для каждого цикл счётчик'),
  PaletteItem('control', 'break', words: 'выйти из цикла прервать'),
  PaletteItem('control', 'continue', words: 'следующий круг'),
  PaletteItem('control', 'function my_action() {\n}', words: 'функция своя команда'),
  PaletteItem('control', 'return', words: 'вернуть выйти из функции'),
  PaletteItem('control', 'try {\n} catch (e) {\n    log(e)\n}', words: 'ошибка перехват'),
];

const _varItems = <PaletteItem>[
  PaletteItem('vars', 'let count = 0', words: 'переменная создать'),
  PaletteItem('vars', 'count = count + 1', words: 'задать изменить переменную'),
  PaletteItem('vars', 'count += 1', words: 'увеличить прибавить'),
  PaletteItem('vars', 'count', value: true, words: 'переменная значение'),
  PaletteItem('vars', '"текст"', value: true, words: 'строка текст'),
  PaletteItem('vars', '10', value: true, words: 'число'),
  PaletteItem('vars', 'true', value: true, words: 'да нет истина ложь логическое'),
];

const _opItems = <PaletteItem>[
  PaletteItem('ops', '1 == 1', value: true, words: 'равно сравнение'),
  PaletteItem('ops', '1 != 2', value: true, words: 'не равно сравнение'),
  PaletteItem('ops', '2 > 1', value: true, words: 'больше сравнение'),
  PaletteItem('ops', '1 < 2', value: true, words: 'меньше сравнение'),
  PaletteItem('ops', 'true && true', value: true, words: 'и оба условия'),
  PaletteItem('ops', 'true || false', value: true, words: 'или любое условие'),
  PaletteItem('ops', '!true', value: true, words: 'не отрицание'),
  PaletteItem('ops', '1 + 1', value: true, words: 'плюс сложить'),
  PaletteItem('ops', '5 - 1', value: true, words: 'минус вычесть'),
  PaletteItem('ops', '2 * 3', value: true, words: 'умножить'),
  PaletteItem('ops', '6 / 2', value: true, words: 'разделить'),
  PaletteItem('ops', '7 % 2', value: true, words: 'остаток'),
];

const _windowItems = <PaletteItem>[
  PaletteItem('windows', 'with_window("Блокнот") {\n}',
      words: 'в окне внутри окна привязать блок координаты от окна'),
];

const _otherItems = <PaletteItem>[
  PaletteItem('other', '// Комментарий', words: 'заметка комментарий'),
];

/// All palette items of a category; [functions] are the script's own
/// functions (name → parameters).
List<PaletteItem> paletteFor(String cat, {Map<String, List<String>> functions = const {}}) {
  final fixed = switch (cat) {
    'control' => _controlItems,
    'vars' => _varItems,
    'ops' => _opItems,
    'other' => _otherItems,
    'windows' => _windowItems,
    _ => const <PaletteItem>[],
  };
  return [
    if (cat != 'vars' && cat != 'ops') ...fixed,
    if (cat == 'vars') ..._varItems.where((i) => !i.value),
    for (final f in functionSpecs)
      if (f.cat == cat && f.statement) PaletteItem(cat, f.example, words: f.label),
    if (cat == 'vars') ..._varItems.where((i) => i.value),
    if (cat == 'ops') ...fixed,
    for (final f in functionSpecs)
      if (f.cat == cat && !f.statement) PaletteItem(cat, f.example, value: true, words: f.label),
    if (cat == 'funcs')
      for (final e in functions.entries)
        PaletteItem(cat, '${e.key}(${e.value.map((_) => '0').join(', ')})', words: e.key),
  ];
}

/// Functions declared in the blocks: name → parameters.
Map<String, List<String>> userFunctions(BlockDoc doc) => {
      for (final n in doc.all)
        if (n.kind == BK.func && n.text.isNotEmpty)
          n.text: [
            for (final p in n.extra.split(','))
              if (p.trim().isNotEmpty) p.trim()
          ],
    };

/// Names of variables, loop variables and parameters used in the blocks.
List<String> variableNames(BlockDoc doc) {
  final out = <String>{};
  for (final n in doc.all) {
    if (n.kind == BK.let || n.kind == BK.forIn) out.add(n.text);
    if (n.kind == BK.tryc && n.text.isNotEmpty) out.add(n.text);
    if (n.kind == BK.func) {
      out.addAll(n.extra.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty));
    }
  }
  return out.toList()..sort();
}
