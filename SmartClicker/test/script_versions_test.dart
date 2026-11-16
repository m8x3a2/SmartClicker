// Past versions of scripts: put aside before an overwrite, the last N kept,
// moved along with a renamed script, cleared.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/app/ui/scripts/versions_dialog.dart' show changeSummary;
import 'package:smart_clicker/core/storage/script_store.dart';
import 'package:smart_clicker/core/storage/script_versions.dart';

void main() {
  late Directory tmp;
  late ScriptStore store;
  late ScriptVersions versions;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sc_versions');
    store = ScriptStore('${tmp.path}${Platform.pathSeparator}scripts');
    versions = ScriptVersions('${tmp.path}${Platform.pathSeparator}versions', keep: 3);
    store.versions = versions;
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  List<String> texts(String name) => [for (final v in versions.of(name)) v.read()];

  test('перед перезаписью прежний текст откладывается; одинаковое и пустое — нет', () {
    store.write('Бой', '');
    store.write('Бой', 'v1'); // the old text was empty: nothing to keep
    expect(texts('Бой'), isEmpty);
    store.write('Бой', 'v2');
    store.write('Бой', 'v2'); // the same text: no new version
    expect(texts('Бой'), ['v1']);
    store.write('Бой', 'v3');
    expect(texts('Бой'), ['v2', 'v1'], reason: 'новые сверху');
    expect(store.read('Бой'), 'v3');
  });

  test('хранятся последние keep; 0 — ничего, лишние удаляются', () {
    for (var i = 1; i <= 6; i++) {
      store.write('Папка/Скрипт', 'v$i');
    }
    expect(texts('Папка/Скрипт'), ['v5', 'v4', 'v3']);
    versions.keep = 1;
    versions.pruneAll();
    expect(texts('Папка/Скрипт'), ['v5']);
    versions.keep = 0;
    versions.pruneAll();
    expect(texts('Папка/Скрипт'), isEmpty);
    expect(Directory(versions.dir).listSync(), isEmpty, reason: 'пустые папки убраны');
    store.write('Папка/Скрипт', 'v7');
    expect(texts('Папка/Скрипт'), isEmpty);
  });

  test('одна секунда: версии не затирают друг друга, порядок верный', () {
    final t = DateTime(2026, 11, 16, 20, 11, 5);
    versions.put('А', 'первая', t);
    versions.put('А', 'вторая', t);
    versions.put('А', 'вторая', t); // the same as the last one
    expect(texts('А'), ['вторая', 'первая']);
    expect(versions.of('А').first.time, t);
  });

  test('скрипт и папка с одним именем не смешиваются; переименование переносит версии', () {
    store.write('А', 'скрипт 1');
    store.write('А', 'скрипт 2');
    store.write('А/Б', 'в папке 1');
    store.write('А/Б', 'в папке 2');
    expect(texts('А'), ['скрипт 1']);
    expect(texts('А/Б'), ['в папке 1']);
    expect(versions.scripts()..sort(), ['А', 'А/Б']);

    versions.rename('А/Б', 'В/Г');
    expect(texts('А/Б'), isEmpty);
    expect(texts('В/Г'), ['в папке 1']);
    // into a name that already had versions: they are merged
    versions.rename('А', 'В/Г');
    expect(texts('В/Г').toSet(), {'скрипт 1', 'в папке 1'});
    expect(texts('А'), isEmpty);
    versions.clear('В/Г');
    expect(versions.scripts(), isEmpty);
  });

  test('подпись «сколько строк изменилось с тех пор»', () {
    expect(changeSummary('a\nb', 'a\nb'), 'как сейчас');
    expect(changeSummary('a\nb\nc', 'a\nx\nc\nd'), 'с тех пор +2 −1 строк');
  });
}
