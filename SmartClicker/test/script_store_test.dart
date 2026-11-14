// ScriptStore on a real temporary folder: deleting all scripts.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/core/storage/script_store.dart';

void main() {
  test('«Удалить все скрипты»: скрипты и пустые папки удаляются, чужие файлы остаются', () {
    final dir = Directory.systemTemp.createTempSync('store_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = ScriptStore(dir.path);
    store.write('Один', 'log(1)');
    store.write('Папка/Два', 'log(2)');
    store.write('Папка/Вложенная/Три', 'log(3)');
    store.createFolder('Пустая');
    File('${dir.path}/Чужая/заметка.txt')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('не скрипт');

    store.deleteAll();

    expect(store.list(), isEmpty);
    expect(store.folders(), ['Чужая']);
    expect(File('${dir.path}/Чужая/заметка.txt').existsSync(), isTrue);
  });
}
