// Templates of the "New script" dialog: ready scripts with fields to fill.

import 'package:flutter/material.dart';

/// What a template parameter holds; the form picks the field by it.
enum ParamKind { text, number, point, region, image, key, color }

class TemplateParam {
  final String id, label;
  final ParamKind kind;
  final String initial;

  /// Shown under the field.
  final String help;
  const TemplateParam(this.id, this.label, this.kind, this.initial,
      {this.help = ''});
}

/// A ready-made script with a few blanks to fill in.
class ScriptTemplate {
  final String id, title, subtitle, description;
  final IconData icon;
  final List<TemplateParam> params;
  final String Function(Map<String, String> v) _build;
  const ScriptTemplate(this.id, this.title, this.subtitle, this.icon,
      this.description, this.params, this._build);

  Map<String, String> get defaults => {for (final p in params) p.id: p.initial};

  /// Code of the script for the values [v] (missing ones are the defaults).
  String build(Map<String, String> v) =>
      _build({...defaults, ...v.map((k, s) => MapEntry(k, s.trim()))});

  /// Problems of the values: parameter id -> message.
  Map<String, String> validate(Map<String, String> v) {
    final out = <String, String>{};
    for (final p in params) {
      final s = (v[p.id] ?? p.initial).trim();
      if (s.isEmpty) {
        out[p.id] = 'Заполните поле';
      } else if (p.kind == ParamKind.number &&
          (num.tryParse(s.replaceAll(',', '.')) == null ||
              num.parse(s.replaceAll(',', '.')) < 0)) {
        out[p.id] = 'Нужно число, 0 или больше';
      } else if (p.kind == ParamKind.color &&
          !RegExp(r'^#?[0-9A-Fa-f]{6}$').hasMatch(s)) {
        out[p.id] = 'Цвет в виде #RRGGBB';
      }
    }
    return out;
  }
}

/// A string literal of the language.
String q(String s) => '"${s.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';

String _num(String s) => s.replaceAll(',', '.');

String _color(String s) => s.startsWith('#') ? s.toUpperCase() : '#${s.toUpperCase()}';

String _header(String title, String text) =>
    '// $title\n${text.split('\n').map((l) => '// $l').join('\n')}\n'
    '// Остановить — клавиша стопа (по умолчанию F12).\n';

const _point = TemplateParam('point', 'Куда нажимать (x, y)', ParamKind.point,
    '50%, 50%',
    help: 'Пиксели или проценты экрана. Точные координаты покажет F6 в редакторе');
const _region = TemplateParam(
    'region', 'Область (x, y, ширина, высота)', ParamKind.region, '40%, 5%, 20%, 6%',
    help: 'Её удобно выделить: Инструменты → Выделить область — координаты скопируются');

TemplateParam _image(String initial) => TemplateParam(
    'image', 'Картинка', ParamKind.image, initial,
    help: 'Имя сохранённой картинки (раздел «Картинки»). Её можно вырезать и потом');

final scriptTemplates = <ScriptTemplate>[
  ScriptTemplate(
    'empty',
    'Пустой скрипт',
    'Начать с чистого листа',
    Icons.note_outlined,
    'Пара строк для начала. Действия удобнее всего записать: кнопка «Запись» (F9).',
    const [],
    (v) => '// Новый скрипт\n\nwait(1s)\nclick(50%, 50%)\n',
  ),
  ScriptTemplate(
    'clicker',
    'Автокликер',
    'Клик в одну точку с паузой',
    Icons.ads_click,
    'Нажимает в одну и ту же точку снова и снова. Можно задать, сколько раз, '
        'или оставить 0 — тогда до остановки.',
    const [
      _point,
      TemplateParam('pause', 'Пауза между кликами, мс', ParamKind.number, '1000',
          help: '1000 мс = 1 секунда'),
      TemplateParam('count', 'Сколько раз (0 — без конца)', ParamKind.number, '0'),
    ],
    (v) {
      final count = num.parse(_num(v['count']!)).round();
      return '${_header('Автокликер', 'Клик в ${v['point']} каждые ${v['pause']} мс.')}\n'
          'use_screen()\n'
          '${count > 0 ? 'repeat ($count) {' : 'repeat {          // без конца'}\n'
          '    click(${v['point']})\n'
          '    wait(${_num(v['pause']!)})\n'
          '}\n';
    },
  ),
  ScriptTemplate(
    'afk',
    'Нажимать клавишу',
    'Анти-AFK: клавиша через случайные паузы',
    Icons.keyboard_outlined,
    'Время от времени нажимает клавишу, чтобы игра или программа не считала '
        'вас отошедшим. Пауза каждый раз случайная — в заданных пределах.',
    const [
      TemplateParam('key', 'Клавиша', ParamKind.key, 'space',
          help: 'space, enter, w, f5, ctrl+s …'),
      TemplateParam('min', 'Пауза от, с', ParamKind.number, '30'),
      TemplateParam('max', 'Пауза до, с', ParamKind.number, '90'),
    ],
    (v) => '${_header('Нажимать клавишу', 'Нажимает ${v['key']} раз в ${v['min']}–${v['max']} с.')}\n'
        'repeat {\n'
        '    key(${q(v['key']!)})\n'
        '    log("нажал", ${q(v['key']!)})\n'
        '    wait(random(${_num(v['min']!)}, ${_num(v['max']!)}) * 1000)\n'
        '}\n',
  ),
  ScriptTemplate(
    'wait_click',
    'Дождаться кнопки и нажать',
    'Один раз, когда появится',
    Icons.touch_app_outlined,
    'Ждёт, пока на экране появится картинка (например, кнопка «Играть» после '
        'загрузки), и нажимает на неё.',
    [
      _image('кнопка'),
      const TemplateParam('timeout', 'Ждать не дольше, с', ParamKind.number, '120'),
    ],
    (v) => '${_header('Дождаться кнопки и нажать', 'Ждёт «${v['image']}» до ${v['timeout']} с и нажимает.')}\n'
        'if (click_image(${q(v['image']!)}, timeout: ${_num(v['timeout']!)}s)) {\n'
        '    log("нажал", ${q(v['image']!)})\n'
        '} else {\n'
        '    log("так и не появилась:", ${q(v['image']!)})\n'
        '}\n',
  ),
  ScriptTemplate(
    'keep_clicking',
    'Нажимать кнопку, когда появится',
    'Следить за экраном без конца',
    Icons.visibility_outlined,
    'Постоянно смотрит на экран и нажимает картинку каждый раз, когда она '
        'появляется: «Продолжить», «Принять», крестик всплывающего окна.',
    [
      _image('кнопка'),
      const TemplateParam('pause', 'Проверять раз в, мс', ParamKind.number, '1000'),
    ],
    (v) => '${_header('Нажимать кнопку, когда появится', 'Следит за «${v['image']}» и нажимает её.')}\n'
        'repeat {\n'
        '    if (click_image(${q(v['image']!)})) {\n'
        '        log("нажал", ${q(v['image']!)})\n'
        '        wait(2s)          // дать окну закрыться\n'
        '    }\n'
        '    wait(${_num(v['pause']!)})\n'
        '}\n',
  ),
  ScriptTemplate(
    'reward',
    'Собирать награду каждые N минут',
    'Раз в N минут нажать картинку',
    Icons.redeem_outlined,
    'Раз в несколько минут пытается нажать картинку (например, «Собрать»). '
        'Если её нет — пишет в лог и ждёт следующего раза.',
    [
      _image('собрать'),
      const TemplateParam('minutes', 'Каждые, мин', ParamKind.number, '30'),
    ],
    (v) => '${_header('Собирать награду', 'Раз в ${v['minutes']} мин нажимает «${v['image']}».')}\n'
        'repeat {\n'
        '    if (click_image(${q(v['image']!)}, timeout: 10s)) {\n'
        '        log("награда собрана")\n'
        '    } else {\n'
        '        log("награды пока нет")\n'
        '    }\n'
        '    wait(${_num(v['minutes']!)}m)\n'
        '}\n',
  ),
  ScriptTemplate(
    'while_visible',
    'Кликать, пока видна картинка',
    'Например, пока не кончатся предметы',
    Icons.repeat,
    'Нажимает картинку снова и снова, пока она есть на экране. Когда пропадёт — '
        'скрипт закончится.',
    [
      _image('предмет'),
      const TemplateParam('pause', 'Пауза между нажатиями, мс', ParamKind.number, '500'),
    ],
    (v) => '${_header('Кликать, пока видна картинка', 'Нажимает «${v['image']}», пока она на экране.')}\n'
        'count = 0\n'
        'while (click_image(${q(v['image']!)})) {\n'
        '    count++\n'
        '    wait(${_num(v['pause']!)})\n'
        '}\n'
        'log("картинка пропала, нажатий:", count)\n',
  ),
  ScriptTemplate(
    'wait_text',
    'Дождаться надписи и нажать',
    'Текст на экране → клик',
    Icons.text_fields,
    'Ждёт, пока в области экрана появится нужный текст (например, «Готово»), '
        'и нажимает в указанную точку.',
    const [
      _region,
      TemplateParam('text', 'Текст', ParamKind.text, 'Готово',
          help: 'Достаточно части слова; регистр не важен'),
      TemplateParam('timeout', 'Ждать не дольше, мин', ParamKind.number, '10'),
      _point,
    ],
    (v) => '${_header('Дождаться надписи и нажать', 'Ждёт «${v['text']}» и нажимает в ${v['point']}.')}\n'
        'if (wait_text(${v['region']}, ${q(v['text']!)}, timeout: ${_num(v['timeout']!)}m)) {\n'
        '    click(${v['point']})\n'
        '    log("надпись появилась — нажал")\n'
        '} else {\n'
        '    log("надпись так и не появилась")\n'
        '}\n',
  ),
  ScriptTemplate(
    'pixel',
    'Ждать цвет и нажать клавишу',
    'Индикатор загорелся → действие',
    Icons.colorize_outlined,
    'Следит за одной точкой экрана. Когда она становится нужного цвета '
        '(полоска заполнилась, индикатор позеленел), нажимает клавишу. '
        'Точку и цвет покажет F6 в редакторе.',
    const [
      _point,
      TemplateParam('color', 'Цвет', ParamKind.color, '#00FF00'),
      TemplateParam('key', 'Клавиша', ParamKind.key, 'space'),
    ],
    (v) => '${_header('Ждать цвет и нажать клавишу', 'Когда ${v['point']} станет ${_color(v['color']!)}, нажимает ${v['key']}.')}\n'
        'repeat {\n'
        '    if (wait_pixel(${v['point']}, ${q(_color(v['color']!))}, timeout: 1h)) {\n'
        '        key(${q(v['key']!)})\n'
        '        log("цвет появился — нажал", ${q(v['key']!)})\n'
        '        // ждём, пока цвет уйдёт, чтобы не нажимать много раз подряд\n'
        '        while (pixel_is(${v['point']}, ${q(_color(v['color']!))})) {\n'
        '            wait(200)\n'
        '        }\n'
        '    }\n'
        '}\n',
  ),
  ScriptTemplate(
    'number',
    'Фармить, пока число меньше N',
    'Читает счётчик на экране',
    Icons.trending_up,
    'Читает число в области экрана (золото, опыт, счётчик) и нажимает картинку, '
        'пока число не дойдёт до нужного.',
    [
      _region,
      const TemplateParam('limit', 'Остановиться на', ParamKind.number, '1000'),
      _image('собрать'),
    ],
    (v) => '${_header('Фармить, пока число меньше ${v['limit']}', 'Число читается в области ${v['region']}.')}\n'
        'repeat {\n'
        '    n = read_number(${v['region']})\n'
        '    if (n == null) {\n'
        '        log("число не прочиталось — проверьте область")\n'
        '    } else if (n >= ${_num(v['limit']!)}) {\n'
        '        log("готово, набрано", n)\n'
        '        break\n'
        '    } else {\n'
        '        click_image(${q(v['image']!)}, timeout: 30s)\n'
        '    }\n'
        '    wait(2s)\n'
        '}\n',
  ),
  ScriptTemplate(
    'repeat',
    'Повторить действия N раз',
    'Цикл для записанных действий',
    Icons.loop,
    'Заготовка цикла: запишите свои действия (кнопка «Запись», F9) и '
        'перенесите строки внутрь фигурных скобок.',
    const [
      TemplateParam('count', 'Сколько раз', ParamKind.number, '10'),
      TemplateParam('pause', 'Пауза после каждого раза, с', ParamKind.number, '2'),
    ],
    (v) => '${_header('Повторить действия', 'Повторяет действия ${v['count']} раз.')}\n'
        'repeat (${num.parse(_num(v['count']!)).round()}) {\n'
        '    // ↓ сюда — ваши действия\n'
        '    click(50%, 50%)\n'
        '    wait(${_num(v['pause']!)}s)\n'
        '}\n'
        'log("готово")\n',
  ),
];
