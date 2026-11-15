// Trash: deleted scripts, folders and pictures are moved in, can be taken
// out, are purged after 30 days, and the trash can be emptied.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/core/storage/trash.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('sc_trash_'));
  tearDown(() => tmp.deleteSync(recursive: true));
  final sep = Platform.pathSeparator;
  String p(String name) => '${tmp.path}$sep$name';

  test('скрипт, папка и картинка переезжают в корзину и читаются после перезапуска', () {
    File(p('Бой.cks')).writeAsStringSync('click(1, 2)');
    Directory(p('Папка$sepПод')).createSync(recursive: true);
    File(p(['Папка', 'Под', 'a.cks'].join(sep))).writeAsStringSync('a');
    File(p('кнопка.png')).writeAsBytesSync([1, 2, 3]);
    final t = Trash(p('trash'));
    t.put('script', 'Бой', p('Бой.cks'));
    t.put('folder', 'Папка', p('Папка'), count: 1);
    t.put('picture', 'кнопка', p('кнопка.png'));
    expect(File(p('Бой.cks')).existsSync(), isFalse);
    expect(Directory(p('Папка')).existsSync(), isFalse);
    expect(File(p('кнопка.png')).existsSync(), isFalse);

    final back = Trash(p('trash'))..load();
    expect([for (final e in back.entries) e.title],
        ['Картинка «кнопка»', 'Папка «Папка» (1)', 'Скрипт «Бой»']);
    final script = back.entries.last;
    expect((back.itemOf(script) as File).readAsStringSync(), 'click(1, 2)');
    final folder = back.entries[1];
    expect(File([back.itemOf(folder)!.path, 'Под', 'a.cks'].join(sep)).existsSync(), isTrue);
    back.forget(script);
    expect(back.entries.length, 2);
    expect(Directory(back.payload(script)).existsSync(), isFalse);
  });

  test('несохранённые правки скрипта сохраняются в корзине', () {
    File(p('Бой.cks')).writeAsStringSync('старое');
    final t = Trash(p('trash'));
    final e = t.put('script', 'Бой', p('Бой.cks'), text: 'на экране');
    expect((t.itemOf(e) as File).readAsStringSync(), 'на экране');
    // never saved at all: only the text on the screen
    final e2 = t.put('script', 'Новый', p('Новый.cks'), text: 'черновик');
    expect((t.itemOf(e2) as File).readAsStringSync(), 'черновик');
  });

  test('старше 30 дней удаляется само; «Очистить корзину»', () {
    File(p('a.cks')).writeAsStringSync('1');
    File(p('b.cks')).writeAsStringSync('2');
    final now = DateTime(2026, 11, 15);
    final t = Trash(p('trash'));
    t.put('script', 'a', p('a.cks'), now: now.subtract(const Duration(days: 31)));
    t.put('script', 'b', p('b.cks'), now: now.subtract(const Duration(days: 2)));
    expect(t.entries.first.daysLeft(now), 28);
    expect(t.purgeOld(now), 1);
    expect([for (final e in t.entries) e.name], ['b']);
    t.clear();
    expect(t.entries, isEmpty);
    expect((Trash(p('trash'))..load()).entries, isEmpty);
  });
}
