// Command palette: which commands fit what is typed, and in what order.

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/app/ui/home/command_palette.dart';

void main() {
  test('все слова запроса должны быть в названии или ключевых словах', () {
    expect(paletteScore('Тест без кликов: включить', 'тестовый режим', 'тест'), 4);
    expect(paletteScore('Тест без кликов: включить', 'тестовый режим', 'режим'), 1);
    expect(paletteScore('Корзина…', 'удалённые вернуть', 'вернуть удал'), 1);
    expect(paletteScore('Открыть скрипт: Бой', '', 'бой'), 3);
    expect(paletteScore('Открыть скрипт: Бой', '', 'фарм'), 0);
    expect(paletteScore('Что угодно', '', ''), 1);
  });
}
