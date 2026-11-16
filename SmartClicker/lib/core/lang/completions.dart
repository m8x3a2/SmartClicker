import 'ast.dart';

/// One suggestion of the editor: a built-in function or a code template.
class Completion {
  final String name;

  /// How the call looks, e.g. `click(x, y)`.
  final String signature;
  final String hint;

  /// Text to insert instead of `name(...)`; `|` marks the caret position.
  final String? snippet;
  const Completion(this.name, this.signature, this.hint, {this.snippet});

  bool get isFunction => snippet == null;

  String get insert =>
      snippet ?? (signature.endsWith('()') ? '$name()' : '$name(|)');
}

/// Shown while typing in the editor. Every function here must exist in
/// `ScriptRuntime` (checked by a test).
const completions = <Completion>[
  // Mouse
  Completion('click', 'click(x, y)',
      'клик левой кнопкой; можно button: "right", count: 2, offset: 10, hold: 100, duration: 300'),
  Completion('double_click', 'double_click(x, y)', 'двойной клик'),
  Completion('right_click', 'right_click(x, y)', 'клик правой кнопкой'),
  Completion('middle_click', 'middle_click(x, y)', 'клик колесом'),
  Completion('move', 'move(x, y, duration: 300)', 'переместить курсор'),
  Completion('drag', 'drag(x1, y1, x2, y2, 400)',
      'зажать, провести и отпустить; последнее число — время, мс'),
  Completion('hold', 'hold(x, y, 1500)', 'зажать кнопку мыши на время, мс'),
  Completion('scroll', 'scroll(3)',
      'колесо: 3 — вниз, -3 — вверх; scroll(3, x, y) — в точке'),
  Completion('mouse_down', 'mouse_down(x, y)', 'зажать кнопку мыши'),
  Completion('mouse_up', 'mouse_up(x, y)', 'отпустить кнопку мыши'),
  Completion('mouse_pos', 'mouse_pos()', 'где курсор: {x, y, px, py}'),
  Completion('mouse_path', 'mouse_path("x,y,мс x,y,мс")',
      'провести курсор по траектории; unit: "%", speed: 2'),
  // Keyboard
  Completion('key', 'key("ctrl+c")',
      'нажать клавишу или сочетание; можно count: 3, hold: 100'),
  Completion('key_down', 'key_down("shift")', 'зажать клавишу'),
  Completion('key_up', 'key_up("shift")', 'отпустить клавишу'),
  Completion('type', 'type("текст")',
      'напечатать текст (любой язык); delay: 50 — пауза между буквами (по умолчанию 50 мс, меняется в настройках); '
          'method: "keys" — настоящими клавишами (для игр и программ, которые не видят обычный ввод)'),
  Completion('paste', 'paste("текст")',
      'вставить текст через буфер обмена (Ctrl+V); то, что вы копировали раньше, вернётся в буфер через 0,5 с'),
  // Time
  Completion('wait', 'wait(1s)', 'пауза: wait(500), wait(1s), wait(800..1200)'),
  Completion('wait_until', 'wait_until("14:30")', 'ждать до указанного времени'),
  Completion('on_key', 'on_key("f5", () => { … })',
      'реакция: когда ВЫ нажали клавишу, выполнить код (основной код подождёт); вернёт номер для off'),
  Completion('every', 'every(5m, () => { … })',
      'реакция: каждые N времени выполнить код, где бы ни был основной цикл'),
  Completion('on_image', 'on_image("картинка", (p) => { … })',
      'реакция: картинка появилась на экране — выполнить код (p — где она); interval: 1s, area: [x, y, w, h]'),
  Completion('off', 'off(id)', 'выключить реакцию (номер из on_key / every / on_image); off() — все'),
  Completion('now', 'now()', 'текущее время в миллисекундах (для замеров)'),
  Completion('elapsed', 'elapsed()', 'сколько миллисекунд работает скрипт'),
  Completion('time', 'time()', 'время строкой: "14:30:05"'),
  Completion('date', 'date()', 'дата строкой: "2026-01-31"'),
  Completion('clock', 'clock()',
      '{year, month, day, weekday, hour, minute, second}'),
  // Screen
  Completion('pixel', 'pixel(x, y)', 'цвет точки: "#RRGGBB"'),
  Completion('pixel_is', 'pixel_is(x, y, "#FF0000", tolerance: 10)',
      'true, если цвет точки совпадает'),
  Completion('wait_pixel', 'wait_pixel(x, y, "#FF0000", timeout: 10s)',
      'ждать цвет в точке; true, если дождались; tolerance: 10'),
  Completion('avg_color', 'avg_color(x, y, w, h)', 'средний цвет области'),
  Completion('find_color', 'find_color("#FF0000", x, y, w, h)',
      'найти цвет: {x, y} или null; без области — весь экран'),
  Completion('read_text', 'read_text(x, y, w, h)',
      'прочитать текст в области экрана (строки через перенос); lang: "en-US", scale: 3'),
  Completion('text_in', 'text_in(x, y, w, h, "Готово")',
      'true, если в области есть такой текст (регистр и лишние пробелы не важны); errors: 1 — допустить ошибку в букве'),
  Completion('similar', 'similar(text, "Начать")',
      'true, если текст похож на образец: распознавание может ошибиться в букве («Враv» ≈ «враг»); errors: 1, percent: 80, case: "exact", part: false'),
  Completion('similarity', 'similarity(text, "Начать")',
      'насколько текст похож на образец, 0..100 (100 — одинаковые)'),
  Completion('wait_text', 'wait_text(x, y, w, h, "Готово", timeout: 10s)',
      'ждать, пока в области появится текст; true, если дождались; interval: 500'),
  Completion('wait_change', 'wait_change(x, y, w, h, timeout: 30s)',
      'ждать, пока область изменится (страница загрузилась, появилось окно); true — изменилась, false — время вышло'),
  Completion('wait_still', 'wait_still(x, y, w, h, still: 1s)',
      'ждать, пока область перестанет меняться на still: (анимация кончилась, ответ допечатался); timeout: 30s'),
  Completion('read_number', 'read_number(x, y, w, h)',
      'число из области экрана (например, счётчик) или null'),
  Completion('screenshot', 'screenshot("имя", x, y, w, h)',
      'сохранить область экрана в картинку имя.png (без области — весь экран)'),
  Completion('find_image', 'find_image("имя")',
      'найти картинку на экране: {x, y} её центра или null; можно область x, y, w, h, tolerance: 20 и scale: "auto" — если картинка могла стать крупнее или мельче'),
  Completion('find_images', 'find_images("имя")',
      'найти ВСЕ места картинки на экране (монеты, враги, клетки): список {x, y} — сверху вниз, слева направо; [] — нет; max: 100, область, tolerance:, scale: — как у find_image'),
  Completion('wait_image', 'wait_image("имя", timeout: 10s)',
      'ждать появления картинки: {x, y} или null'),
  Completion('click_image', 'click_image("имя")',
      'кликнуть по картинке, если она есть; true/false; timeout: 5s — подождать её появления'),
  Completion('color_diff', 'color_diff("#FF0000", "#F00000")',
      'разница цветов 0..255'),
  Completion('screen_size', 'screen_size()', 'размер экрана: {w, h}'),
  // Windows and processes
  Completion('active_window', 'active_window()',
      'активное окно: {title, process, pid, x, y, w, h}'),
  Completion('windows', 'windows()', 'массив всех окон'),
  Completion('window_exists', 'window_exists("Game")', 'есть ли такое окно'),
  Completion('is_window_active', 'is_window_active("Game")',
      'активно ли это окно сейчас'),
  Completion('focus_window', 'focus_window("Game")',
      'вывести окно на передний план'),
  Completion('set_window_bounds', 'set_window_bounds("Game", 0, 0, 1280, 720)',
      'положение и размер окна: x, y, ширина, высота'),
  Completion('use_window', 'use_window("Game")',
      'считать координаты от этого окна (до конца скрипта)'),
  Completion('use_screen', 'use_screen()',
      'снова считать координаты от всего экрана'),
  Completion('require_window', 'require_window("Game")',
      'клики и клавиши — только в это окно: не спереди — выведет вперёд '
      '(focus: false — ждать, пока станет активным); null — снять'),
  Completion('is_process_running', 'is_process_running("game.exe")',
      'запущена ли программа'),
  Completion('kill_process', 'kill_process("game.exe")', 'закрыть программу'),
  Completion('launch', 'launch("notepad.exe")',
      'запустить программу, файл или ссылку; new: true — ещё одну копию'),
  Completion('run_command', 'run_command("ipconfig")',
      'выполнить команду: {code, out, err}'),
  // System and data
  Completion('battery_level', 'battery_level()', 'заряд батареи 0..100 или null'),
  Completion('is_charging', 'is_charging()', 'идёт ли зарядка'),
  Completion('is_network_connected', 'is_network_connected()', 'есть ли сеть'),
  Completion('cpu_usage', 'cpu_usage()',
      'загрузка процессора, %; cpu_usage("game.exe") — сколько берёт программа (null — не запущена); interval: 500 — время замера, мс'),
  Completion('ram_usage', 'ram_usage()',
      'занятая память, %; ram_usage("game.exe") — память программы в МБ (null — не запущена)'),
  Completion('ram_info', 'ram_info()', 'память компьютера: {total, free, used} в МБ'),
  Completion('system_power', 'system_power("sleep")',
      '"lock" — блокировка, "sleep" — сон, "hibernate", "shutdown" — выключить, "restart", "logoff". Кроме "lock" — только если разрешено в настройках'),
  Completion('get_clipboard', 'get_clipboard()', 'текст из буфера обмена'),
  Completion('set_clipboard', 'set_clipboard("текст")',
      'положить текст в буфер обмена'),
  Completion('clip_history', 'clip_history()',
      'история буфера (раздел «Буфер»): список {n, kind, text, files, image, time}, 1 — самое новое'),
  Completion('paste_clip', 'paste_clip(1)', 'вставить запись истории буфера номер n (Ctrl+V); 1 — самая новая'),
  Completion('copy_clip', 'copy_clip(1)', 'положить запись истории буфера номер n в буфер, не вставляя'),
  Completion('clip_add', 'clip_add("текст")', 'добавить текст в свою «стопку» скрипта (вставить — paste_next / paste_all)'),
  Completion('clip_add_file', 'clip_add_file("отчёт.pdf")',
      'добавить файл в «стопку» (имя без пути — папка files; снимок screenshot("имя") — "имя.png")'),
  Completion('paste_next', 'paste_next()', 'вставить следующее из «стопки» и убрать его; false — стопка пуста'),
  Completion('paste_all', 'paste_all()',
      'вставить всю «стопку» разом: тексты подряд (separator: "\\n"), с файлами — всё одним списком файлов'),
  Completion('clip_count', 'clip_count()', 'сколько осталось в «стопке»'),
  Completion('clip_clear', 'clip_clear()', 'очистить «стопку»'),
  Completion('read_file', 'read_file("a.txt")', 'прочитать текстовый файл'),
  Completion('write_file', 'write_file("a.txt", "текст")', 'записать файл'),
  Completion('append_file', 'append_file("a.txt", "текст")',
      'дописать в конец файла'),
  Completion('file_exists', 'file_exists("a.txt")', 'есть ли файл'),
  Completion('read_json', 'read_json("задание.json", "ключ", значение_если_нет)',
      'прочитать JSON-файл: весь или одно значение по ключу ("a.b" — внутрь); файла или ключа нет — третий аргумент'),
  Completion('write_json', 'write_json("задание.json", "ключ", значение)',
      'записать значение по ключу в JSON-файл (остальное в файле остаётся); с двумя аргументами — весь файл'),
  Completion('wait_file', 'wait_file("задание.json", key: "ready", value: true)',
      'ждать, пока файл изменится (или появится); с key: — пока значение не станет value:; timeout:, interval: 1000'),
  Completion('export_vars', 'export_vars("состояние.json")',
      'записать переменные скрипта в JSON-файл — чтобы другая программа видела, где скрипт'),
  Completion('save_data', 'save_data("ключ", значение)',
      'запомнить значение между запусками'),
  Completion('load_data', 'load_data("ключ", 0)',
      'прочитать сохранённое значение; второе — если его нет'),
  // Other
  Completion('log', 'log("текст", значение)', 'написать в лог'),
  Completion('warn', 'warn("текст")', 'предупреждение в лог'),
  Completion('notify', 'notify("Заголовок", "Текст")', 'всплывающая плашка'),
  Completion('beep', 'beep()', 'системный звук: beep(), beep("ok"), beep("warn"), beep("error")'),
  Completion('sound', 'sound("сигнал")',
      'проиграть звук .wav из папки files, не дожидаясь конца; sound() — остановить'),
  Completion('ask', 'ask("Сколько раз?", 10)',
      'спросить значение при запуске: число, текст, true/false или options: ["а", "б"]; ответ запоминается'),
  Completion('exit', 'exit()', 'завершить скрипт'),
  Completion('run_script', 'run_script("Имя скрипта")',
      'выполнить другой скрипт; его функции остаются доступны'),
  Completion('use', 'use("Общее/бой")',
      'подключить функции другого скрипта: его функции работают здесь, остальной его код (клики, проверки) не выполняется'),
  Completion('set_option', 'set_option("human", true)',
      'настройки: "human", "click_offset", "time_jitter"'),
  Completion('random', 'random(1, 10)', 'случайное число от 1 до 10'),
  Completion('random_int', 'random_int(1, 10)', 'случайное целое от 1 до 10'),
  Completion('chance', 'chance(30%)', 'true с вероятностью 30%'),
  Completion('pick', 'pick([1, 2, 3])', 'случайный элемент массива'),
  Completion('str', 'str(x)', 'превратить в строку'),
  Completion('int', 'int(x)', 'превратить в целое число'),
  Completion('float', 'float(x)', 'превратить в дробное число'),
  Completion('len', 'len(x)', 'длина строки или массива'),
  Completion('type_of', 'type_of(x)', 'тип значения'),
  Completion('keys', 'keys(o)', 'ключи объекта'),
  Completion('to_json', 'to_json(x)', 'значение → строка JSON'),
  Completion('from_json', 'from_json(s)', 'строка JSON → значение'),
  // Templates
  Completion('with_window', 'with_window("Game") { ... }',
      'внутри блока координаты от окна и нажатия только в него (выведет вперёд); '
      'после блока — как было. Окна нет — ждёт до 30 с (timeout:); restore: true — '
      'потом вернуть вперёд прежнее окно',
      snippet: 'with_window("|") {\n    \n}'),
  Completion('repeat', 'repeat (10) { ... }', 'повторить несколько раз',
      snippet: 'repeat (|) {\n    \n}'),
  Completion('if', 'if (условие) { ... }', 'условие',
      snippet: 'if (|) {\n    \n}'),
  Completion('while', 'while (условие) { ... }', 'цикл, пока условие верно',
      snippet: 'while (|) {\n    \n}'),
  Completion('for', 'for (i in 1..10) { ... }', 'цикл со счётчиком',
      snippet: 'for (i in 1..|) {\n    \n}'),
  Completion('function', 'function имя(a, b) { ... }', 'своя функция',
      snippet: 'function |() {\n    \n}'),
  Completion('try', 'try { ... } catch (e) { ... }', 'перехват ошибок',
      snippet: 'try {\n    |\n} catch (e) {\n    log(e)\n}'),
];

/// Named arguments, explained when the mouse hovers over them.
const paramHints = <String, String>{
  'timeout': 'сколько ждать, прежде чем сдаться (timeout: 5s). Не дождались — функция вернёт false. В with_window — сколько ждать, пока окно появится (по умолчанию 30s; 0 — не ждать)',
  'tolerance': 'допустимое отличие цвета, 0..255: 0 — точное совпадение, 25 — похожий оттенок',
  'engine': 'способ распознавания текста: "windows" — быстрое, "paddle" — точное (PaddleOCR). По умолчанию — выбранный в окне «Картинки и текст»',
  'lang': 'язык для быстрого распознавания (engine: "windows"): "ru", "en-US"; по умолчанию — языки Windows',
  'scale': 'в read_text — во сколько раз увеличить область перед распознаванием (по умолчанию подбирается само); '
      'в find_image / wait_image / click_image — масштаб картинки на экране: 1.5, диапазон 0.5..2 или "auto" (ищет дольше)',
  'interval': 'как часто проверять, мс (в cpu_usage — сколько длится замер)',
  'button': 'кнопка мыши: "left", "right" или "middle"',
  'count': 'сколько раз нажать подряд',
  'offset': 'случайный разброс точки клика, ± пикселей',
  'hold': 'сколько миллисекунд держать нажатой',
  'duration': 'за сколько миллисекунд плавно довести курсор до точки',
  'delay': 'пауза между буквами, мс (по умолчанию 50 — из настроек; 0 — всё разом, но тогда некоторые программы, например Блокнот Windows 11, теряют буквы)',
  'method': 'как печатать type: "auto" (по умолчанию) — буквы Юникодом, цифры и пробел клавишами, ни одной неверной буквы; '
      '"keys" — всё, что есть в раскладке окна, настоящими клавишами (видят игры и горячие клавиши программ; смена раскладки во время ввода даст другие буквы); '
      '"unicode" — всё символами Юникода (раскладка не важна, но игры их обычно не видят)',
  'unit': '"%" — координаты траектории заданы в процентах',
  'speed': 'скорость траектории: 2 — вдвое быстрее, 0.5 — вдвое медленнее',
  'restore': 'with_window: true — после блока вернуть вперёд окно, которое было активно до него; '
      'paste: false — оставить вставленный текст в буфере (по умолчанию через 0,5 с в буфер возвращается то, что было скопировано раньше)',
  'focus': 'require_window / with_window: true (по умолчанию) — окно не спереди, вывести его вперёд; false — ждать, пока его сделают активным',
  'new': 'true — открыть ещё одну копию программы, даже если она уже запущена',
  'wait': 'false — не ждать, пока команда завершится',
  'horizontal': 'true — крутить колесо вбок (горизонтальная прокрутка)',
  'options': 'варианты ответа для выпадающего списка: options: ["быстро", "медленно"]',
  'errors': 'сколько букв может быть неверно, пропущено или лишнее: errors: 1. В similar по умолчанию — 1 на каждые 4 буквы образца, в text_in / wait_text — 0',
  'percent': 'similar: вместо errors — сколько процентов образца должно совпасть (percent: 80); '
      'wait_change / wait_still: сколько процентов области считается изменением (по умолчанию 1)',
  'still': 'wait_still: сколько времени область должна не меняться (по умолчанию 1s)',
  'max': 'find_images: сколько мест найти самое большее (по умолчанию 100)',
  'case': '"ignore" (по умолчанию) — заглавные и строчные буквы не различаются; "exact" — различаются',
  'part': 'true (по умолчанию) — образец может быть частью текста («Начать» в «Начать игру»); false — весь текст целиком',
  'area': 'on_image: где искать картинку — [x, y, ширина, высота] (по умолчанию весь экран)',
  'separator': 'paste_all: чем разделять тексты (по умолчанию перевод строки)',
  'key': 'wait_file: ключ в JSON-файле, значение которого ждать ("a.b" — внутрь)',
  'value': 'wait_file: какое значение ждать по key: (без value: — любое «да»: true, не 0, не пустое)',
  'lookalike': 'true (по умолчанию) — похожие русские и латинские буквы считаются одинаковыми (Р и P, о и o)',
};

final _functionDecl = RegExp(r'function\s+([A-Za-z_]\w*)\s*\(([^)\n]*)\)');

/// Functions declared in the script itself.
List<Completion> scriptFunctions(String source) => [
      for (final m in _functionDecl.allMatches(source))
        Completion(m[1]!, '${m[1]}(${m[2]!.trim()})', 'функция из этого скрипта'),
    ];

/// Functions of the scripts connected with use("…") in [source]
/// ([scriptSource] gives their text): offered like the script's own. Only
/// functions written from the start of a line (top level) are given by use.
List<Completion> usedFunctions(String source, String? Function(String name)? scriptSource) {
  if (scriptSource == null) return const [];
  final out = <Completion>[];
  final seen = <String>{};
  for (final m in _useCall.allMatches(source)) {
    final name = m[2]!;
    if (!seen.add(name.toLowerCase())) continue;
    final src = scriptSource(name);
    if (src == null) continue;
    for (final f in _topFunction.allMatches(src)) {
      out.add(Completion(f[1]!, '${f[1]}(${f[2]!.trim()})', 'функция из «$name» (подключена use)'));
    }
  }
  return out;
}

final _useCall = RegExp(r'''\buse\s*\(\s*(["'])([^"'\n]+)\1''');
final _topFunction = RegExp(r'^function\s+([A-Za-z_]\w*)\s*\(([^)\n]*)\)', multiLine: true);

final _camelHump = RegExp('[A-Z]');

/// Finds a function by name; camelCase aliases are understood too.
Completion? completionFor(String name, [List<Completion> extra = const []]) {
  final snake =
      name.replaceAllMapped(_camelHump, (m) => '_${m[0]!.toLowerCase()}');
  for (final c in [...extra, ...completions]) {
    final callable = c.isFunction || scopedCalls.contains(c.name); // with_window() { }
    if (callable && (c.name == name || c.name == snake)) return c;
  }
  return null;
}

/// Suggestions for an identifier being typed: names that start with
/// [prefix] first, then names that contain it. An exact match is not offered.
List<Completion> suggest(String prefix, [List<Completion> extra = const []]) {
  final p = prefix.toLowerCase();
  if (p.isEmpty) return const [];
  final starts = <Completion>[], contains = <Completion>[];
  final seen = <String>{};
  for (final c in [...extra, ...completions]) {
    final n = c.name.toLowerCase();
    if (n == p || !seen.add(n)) continue;
    if (n.startsWith(p)) {
      starts.add(c);
    } else if (p.length >= 3 && n.contains(p)) {
      contains.add(c);
    }
  }
  return [...starts, ...contains];
}
