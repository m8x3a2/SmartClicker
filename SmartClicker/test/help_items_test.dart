// Items of the help that are copied with one click.

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/app/help/help_items.dart';
import 'package:smart_clicker/app/ui/help/help_screen.dart' show helpSections;

void main() {
  test('пункты: список, пример кода без отступа, строка справочника', () {
    const text = '''
КАРТИНКИ
--------
  • Найти картинку можно командой find_image, она
    вернёт точку или null.
  • Второй пункт.

    p = find_image("старт")       // где она?
    if (p) {
        click(p)
    }

find_image("имя") → {x, y} или null
   {x, y} — центр найденной картинки
''';
    final items = helpItems(text);
    expect(items.map((i) => i.line), [2, 4, 6, 11]);
    expect(items[0].text, 'Найти картинку можно командой find_image, она вернёт точку или null.');
    expect(items[0].lines, 2);
    expect(items[1].text, 'Второй пункт.');
    expect(items[2].code, isTrue);
    expect(items[2].text, 'p = find_image("старт")       // где она?\nif (p) {\n    click(p)\n}');
    expect(items[3].text, 'find_image("имя") → {x, y} или null {x, y} — центр найденной картинки');
  });

  test('код и текст различаются по русским словам вне кавычек и комментариев', () {
    expect(isCodeLine('    click_image("старт")  // нажать, если видна'), isTrue);
    expect(isCodeLine('    // только комментарий'), isTrue);
    expect(isCodeLine('    вернёт точку или null.'), isFalse);
    expect(isCodeLine('  • click(1, 2)'), isFalse);
  });

  test('во всех разделах справки есть пункты, примеры кода копируются без отступа', () {
    for (final s in helpSections) {
      if (s.text == null) continue;
      final items = helpItems(s.text!);
      expect(items, isNotEmpty, reason: s.title);
      for (final it in items.where((i) => i.code)) {
        expect(it.text.startsWith(' '), isFalse, reason: '${s.title}: ${it.text}');
      }
    }
  });
}
