// The click map of a test run: what the engine reports and the window.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/app/state/app_controller.dart';
import 'package:smart_clicker/app/ui/scripts/click_map_dialog.dart';
import 'package:smart_clicker/core/engine/runtime.dart';
import 'package:smart_clicker/core/vision/bitmap.dart';
import 'package:smart_clicker/core/vision/png.dart';
import 'package:smart_clicker/platform/stub_backend.dart';

Future<List<Map<String, Object?>>> acts(String source, {bool dry = true, String? files}) async {
  final events = <Map<String, Object?>>[];
  final r = await ScriptRuntime(
          StubBackend(), {'main': 't', 'source': source, 'dryRun': dry, 'filesDir': ?files}, events.add,
          random: Random(1))
      .runMain();
  expect(r['error'], isNull, reason: '$r');
  return events.where((e) => e['t'] == 'act').toList();
}

void main() {
  test('тестовый прогон сообщает действия: точка, строка, вид', () async {
    // A bright picture that the stub's black screen does not have.
    final dir = Directory.systemTemp.createTempSync('sc-map');
    addTearDown(() => dir.deleteSync(recursive: true));
    final px = Uint8List(4 * 4 * 4)..fillRange(0, 64, 255);
    File('${dir.path}${Platform.pathSeparator}кнопка.png').writeAsBytesSync(pngEncode(Bitmap(4, 4, px)));
    final a = await acts(
        'click(100, 200)\nmove(5, 6)\nkey("enter")\n'
        'click_image("кнопка")\ndrag(1, 2, 3, 4)\nscroll(2, 50, 60)',
        files: dir.path);
    expect(a.map((e) => e['k']), ['press', 'move', 'press', 'miss', 'press', 'move']);
    expect(a.map((e) => e['l']), [1, 2, 3, 4, 5, 6]);
    expect([a[0]['x'], a[0]['y']], [100, 200]);
    expect(a[2]['x'], isNull); // a key has no point
    expect(a[3]['m'], contains('не найдена'));

    final m = [for (var i = 0; i < a.length; i++) MapAction.of(i + 1, a[i])];
    expect(m.map((x) => x.kind), ['press', 'move', 'key', 'miss', 'press', 'move']);
    expect(m.where((x) => x.hasPoint).map((x) => x.n), [1, 2, 5, 6]);

    // A real run reports nothing; a long loop — only the first ones.
    expect(await acts('click(1, 1)', dry: false), isEmpty);
    final many = await acts('repeat (400) { click(1, 1) }');
    expect(many.length, 300);
  });

  testWidgets('окно карты: список действий со строками', (tester) async {
    final lines = <int>[];
    final map = ClickMap('Фарм', DateTime(2026, 11, 15, 10), 4, 4, opaque(Uint8List(64)), const [
      MapAction(1, 'клик → 1, 1', 3, 1, 1, 'press'),
      MapAction(2, 'клавиша enter', 4, null, null, 'key'),
      MapAction(3, 'клик → 2, 2', 7, 2, 2, 'press', other: true),
    ], 3);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
            onPressed: () => showClickMap(context, map, onLine: lines.add),
            child: const Text('open')),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    expect(find.textContaining('Карта кликов: «Фарм»'), findsOneWidget);
    expect(find.text('клавиша enter'), findsOneWidget);
    expect(find.text('строка 3 · 1, 1'), findsOneWidget);
    expect(find.textContaining('другого скрипта'), findsOneWidget);
    await tester.tap(find.text('клавиша enter'));
    await tester.tap(find.textContaining('другого скрипта')); // no line to show there
    expect(lines, [4]);
  });
}
