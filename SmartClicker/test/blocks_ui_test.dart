import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/app/ui/blocks/blocks_editor.dart';

void main() {
  Future<TextEditingController> pump(WidgetTester tester, String code,
      {BlocksHost host = const BlocksHost(), double width = 1200}) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = TextEditingController(text: code);
    final line = ValueNotifier<int>(0);
    final breaks = ValueNotifier<Set<int>>({});
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BlocksEditor(
          controller: c,
          currentLine: line,
          errorLine: line,
          breakpoints: breaks,
          onBreakpoint: (l) {
            final s = {...breaks.value};
            if (!s.remove(l)) s.add(l);
            breaks.value = s;
          },
          host: host,
        ),
      ),
    ));
    await tester.pump();
    return c;
  }

  testWidgets('блоки показывают скрипт словами', (tester) async {
    await pump(tester, '// Начало\nrepeat (5) {\n    click(50%, 50%)\n    wait(1s)\n}\nlog("Готово")\n');
    expect(find.text('повторить'), findsWidgets);
    expect(find.text('раз'), findsWidgets);
    expect(find.text('кликнуть'), findsOneWidget);
    expect(find.text('ждать'), findsWidgets);
    expect(find.text('в лог'), findsWidgets);
    expect(find.text('Начало'), findsOneWidget);
    // Values are editable fields.
    expect(find.widgetWithText(TextField, '5'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Готово'), findsOneWidget);
  });

  testWidgets('правка числа в блоке меняет код', (tester) async {
    final c = await pump(tester, 'repeat (5) {\n    wait(1s)\n}\n');
    await tester.enterText(find.widgetWithText(TextField, '5'), '7');
    await tester.pump();
    expect(c.text, 'repeat (7) {\n    wait(1s)\n}\n');
    // Text is written in quotes, numbers as they are.
    await tester.enterText(find.widgetWithText(TextField, '1s'), '2s');
    await tester.pump();
    expect(c.text, 'repeat (7) {\n    wait(2s)\n}\n');
    // A wrong expression is not written.
    await tester.enterText(find.widgetWithText(TextField, '2s'), '2s +');
    await tester.pump();
    expect(c.text, contains('wait(2s)'));
  });

  testWidgets('текст в гнезде пишется в кавычках', (tester) async {
    final c = await pump(tester, 'type("Привет")\n');
    await tester.enterText(find.widgetWithText(TextField, 'Привет'), 'Сказал "да"');
    await tester.pump();
    expect(c.text, 'type("Сказал \\"да\\"")\n');
  });

  testWidgets('щелчок по блоку в списке добавляет его', (tester) async {
    final c = await pump(tester, 'wait(1s)\n');
    await tester.tap(find.text('Мышь'));
    await tester.pump();
    await tester.tap(find.text('кликнуть').first, warnIfMissed: false);
    await tester.pump();
    expect(c.text, 'wait(1s)\nclick(50%, 50%)\n');
    // The new block is selected: the next one goes after it.
    await tester.tap(find.text('Клавиши'));
    await tester.pump();
    await tester.tap(find.text('нажать клавишу').first, warnIfMissed: false);
    await tester.pump();
    expect(c.text, 'wait(1s)\nclick(50%, 50%)\nkey("enter")\n');
  });

  testWidgets('выделенный блок удаляется клавишей Delete, Ctrl+Z возвращает', (tester) async {
    final c = await pump(tester, 'wait(1s)\nclick(10, 20)\n');
    await tester.tap(find.text('кликнуть'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(c.text, 'wait(1s)\n');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(c.text, 'wait(1s)\nclick(10, 20)\n');
    // Ctrl+D duplicates.
    await tester.tap(find.text('ждать'));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(c.text, 'wait(1s)\nwait(1s)\nclick(10, 20)\n');
  });

  testWidgets('блок перетаскивается из списка внутрь цикла', (tester) async {
    final c = await pump(tester, 'repeat (3) {\n}\n');
    await tester.tap(find.text('Ожидание'));
    await tester.pump();
    final from = tester.getCenter(find.text('ждать').first);
    final to = tester.getCenter(find.text('пусто — перетащите блоки сюда'));
    final g = await tester.startGesture(from);
    await g.moveBy(const Offset(30, 0));
    await tester.pump();
    await g.moveTo(to);
    await tester.pump();
    await g.moveBy(const Offset(2, 2));
    await tester.pump();
    await g.up();
    await tester.pump();
    expect(c.text, 'repeat (3) {\n    wait(1s)\n}\n');
  });

  testWidgets('блок скрипта перетаскивается на новое место и в корзину', (tester) async {
    final c = await pump(tester, 'wait(1s)\nkey("enter")\n');
    // Move "key" above "wait": drop on the upper half of the first block.
    final from = tester.getCenter(find.text('нажать клавишу'));
    final waitBox = tester.getRect(find.text('ждать'));
    final g = await tester.startGesture(from);
    await g.moveBy(const Offset(0, -30));
    await tester.pump();
    await g.moveTo(Offset(waitBox.center.dx, waitBox.top));
    await tester.pump();
    await g.moveBy(const Offset(0, -1));
    await tester.pump();
    await g.up();
    await tester.pump();
    expect(c.text, 'key("enter")\nwait(1s)\n');
    // Dropped on the palette, a block is deleted.
    final g2 = await tester.startGesture(tester.getCenter(find.text('ждать')));
    await g2.moveBy(const Offset(-40, 0));
    await tester.pump();
    await g2.moveTo(const Offset(150, 400));
    await tester.pump();
    expect(find.textContaining('чтобы удалить'), findsOneWidget);
    await g2.up();
    await tester.pump();
    expect(c.text, 'key("enter")\n');
  });

  testWidgets('значение из списка встаёт в гнездо условия', (tester) async {
    final c = await pump(tester, 'if (true) {\n}\n');
    await tester.tap(find.text('Экран'));
    await tester.pump();
    final from = tester.getCenter(find.text('цвет точки').first);
    final slot = tester.getCenter(find.text('да').first);
    final g = await tester.startGesture(from);
    await g.moveBy(const Offset(30, 0));
    await tester.pump();
    await g.moveTo(slot);
    await tester.pump();
    await g.up();
    await tester.pump();
    expect(c.text, 'if (pixel(50%, 50%)) {\n}\n');
    // Nested slots are editable too.
    await tester.enterText(find.widgetWithText(TextField, '50%').first, '10%');
    await tester.pump();
    expect(c.text, 'if (pixel(10%, 50%)) {\n}\n');
  });

  testWidgets('правка кода сразу перестраивает блоки, ошибка — предупреждение', (tester) async {
    final c = await pump(tester, 'wait(1s)\n');
    c.text = 'wait(1s)\nkey("a")\n';
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('нажать клавишу'), findsOneWidget);
    c.text = 'wait(1s)\nkey("a"\n';
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('В коде сейчас ошибка (строка'), findsOneWidget);
    // The last good blocks stay visible.
    expect(find.text('нажать клавишу'), findsOneWidget);
    c.text = 'log(1)\n';
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('ошибка'), findsNothing);
    expect(find.text('в лог'), findsWidgets);
  });

  testWidgets('кнопка «+» добавляет параметр, крестик убирает', (tester) async {
    final c = await pump(tester, 'click(10, 20)\n');
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('кнопка (button)'));
    await tester.pumpAndSettle();
    expect(c.text, 'click(10, 20, button: "right")\n');
    expect(find.text('правая'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(c.text, 'click(10, 20)\n');
  });

  testWidgets('прицел берёт точку и цвет', (tester) async {
    String? mode;
    final c = await pump(tester, 'wait_pixel(1, 2, "#000000")\n',
        host: BlocksHost(pick: (m, line, done) {
          mode = m;
          done(['30%', '40%'], '#12AB34');
        }));
    await tester.tap(find.byIcon(Icons.my_location));
    await tester.pump();
    expect(mode, 'point');
    expect(c.text, 'wait_pixel(30%, 40%, "#12AB34")\n');
  });

  testWidgets('поиск блока по словам', (tester) async {
    await pump(tester, '');
    await tester.enterText(find.widgetWithText(TextField, 'Найти блок…'), 'картинк');
    await tester.pump();
    expect(find.text('кликнуть по картинке'), findsOneWidget);
    expect(find.text('ждать картинку'), findsOneWidget);
    expect(find.textContaining('Найдено:'), findsOneWidget);
  });

  testWidgets('в узком месте список блоков всплывает и закрывается после добавления', (tester) async {
    final c = await pump(tester, 'wait(1s)\n', width: 600);
    expect(find.text('Найти блок…'), findsNothing);
    await tester.tap(find.text('Мышь'));
    await tester.pump();
    expect(find.text('Найти блок…'), findsOneWidget);
    await tester.tap(find.text('кликнуть').first, warnIfMissed: false);
    await tester.pump();
    expect(c.text, 'wait(1s)\nclick(50%, 50%)\n');
    expect(find.text('Найти блок…'), findsNothing);
  });

  testWidgets('правая кнопка: меню гнезда и меню блока', (tester) async {
    final c = await pump(tester, 'wait(1s)\n');
    await tester.tapAt(tester.getCenter(find.widgetWithText(TextField, '1s')),
        buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(find.text('Изменить как код…'), findsOneWidget);
    expect(find.text('Дублировать'), findsNothing, reason: 'меню блока не открывается поверх');
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.text('ждать')),
        buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Дублировать'));
    await tester.pumpAndSettle();
    expect(c.text, 'wait(1s)\nwait(1s)\n');
  });
}
