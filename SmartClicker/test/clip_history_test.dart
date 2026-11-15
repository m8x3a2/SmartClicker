// Clipboard history: adding, the same copied twice, limits on count and
// size, pinned items, saving and reading back.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/core/storage/clip_history.dart';
import 'package:smart_clicker/core/storage/settings.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('sc_clip_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  var n = 0;
  ClipItem text(String t) => ClipItem(
    id: 'id${n++}',
    kind: 'text',
    text: t,
    bytes: t.length,
    at: DateTime(2026, 11, 15, 12, 0, n),
  );

  test('новое сверху; то же самое ещё раз — поднимается, а не дублируется', () {
    final h = ClipHistory(tmp.path);
    for (final t in ['а', 'б', 'в']) {
      h.add(text(t), maxItems: 30, maxBytes: 1000);
    }
    h.add(text('а'), maxItems: 30, maxBytes: 1000);
    expect([for (final i in h.items) i.text], ['а', 'в', 'б']);
  });

  test('лимиты: число и размер; закреплённые не удаляются', () {
    final h = ClipHistory(tmp.path);
    h.add(text('первое'), maxItems: 3, maxBytes: 1000);
    h.items.first.pinned = true;
    for (final t in ['2', '3', '4', '5']) {
      h.add(text(t), maxItems: 3, maxBytes: 1000);
    }
    expect([for (final i in h.items) i.text], ['5', '4', 'первое']);
    h.add(text('x' * 20), maxItems: 30, maxBytes: 25);
    expect(
      [for (final i in h.items) i.text],
      ['x' * 20, 'первое'],
      reason: 'старые ушли по размеру, новая и закреплённая остались',
    );
    h.add(text('y' * 40), maxItems: 30, maxBytes: 25);
    expect([for (final i in h.items) i.text], ['первое'], reason: 'одна запись больше лимита — не хранится');
  }, skip: false);

  test(
    'сохраняется, читается, файлы и картинки; очистка оставляет закреплённые',
    () {
      final h = ClipHistory(tmp.path);
      h.add(
        ClipItem(
          id: 'f',
          kind: 'files',
          files: [r'C:\a\отчёт.docx', r'C:\a\b.png'],
          bytes: 0,
          at: DateTime(2026),
        ),
        maxItems: 30,
        maxBytes: 1000,
      );
      File('${tmp.path}${Platform.pathSeparator}img.png')
          .writeAsBytesSync([1, 2, 3]);
      h.add(
        ClipItem(
          id: 'i',
          kind: 'image',
          image: 'img.png',
          w: 4,
          h: 3,
          bytes: 3,
          at: DateTime(2026),
        ),
        maxItems: 30,
        maxBytes: 1000,
      );
      h.add(text('заметка'), maxItems: 30, maxBytes: 1000);
      h.items.last.pinned = true; // the files
      h.save();

      final back = ClipHistory(tmp.path)..load();
      expect(back.items.length, 3);
      expect(back.items[1].title, 'Картинка 4×3');
      expect(back.items[2].title, '2 файлов: отчёт.docx, b.png');
      expect(back.items[2].pinned, isTrue);

      back.clear();
      expect([for (final i in back.items) i.kind], ['files']);
      expect(
        File('${tmp.path}${Platform.pathSeparator}img.png').existsSync(),
        isFalse,
      );
    },
  );

  test('настройки: история выключена, 30 записей, 10 МБ, Win+Alt+V', () {
    final s = Settings();
    expect(s.clipHistory, isFalse);
    expect(s.clipMaxItems, 30);
    expect(s.clipMaxMb, 10);
    expect(s.clipKey, 'win+alt+v');
    final back = Settings.fromJson({...s.toJson(), 'clipMaxItems': 99999});
    expect(back.clipMaxItems, 5000);
  });

  test('по очереди: от старых к новым, вставленное — в корзину, можно вернуть', () {
    final h = ClipHistory(tmp.path);
    for (final t in ['первый', 'второй', 'третий']) {
      h.add(text(t), maxItems: 30, maxBytes: 1000);
    }
    h.items.last.pinned = true; // «первый» закреплён — не уходит
    expect(h.nextInLine!.text, 'второй');
    h.toTrash(h.nextInLine!);
    expect(h.nextInLine!.text, 'третий');
    expect([for (final i in h.trash) i.text], ['второй']);
    h.save();
    final back = ClipHistory(tmp.path)..load();
    expect(back.trash.single.text, 'второй');
    back.restore(back.trash.single);
    expect(back.items.first.text, 'второй');
    expect(back.trash, isEmpty);
    back.toTrash(back.items.first);
    back.emptyTrash();
    expect(back.trash, isEmpty);
  });
}
