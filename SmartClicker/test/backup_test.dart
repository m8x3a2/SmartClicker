// Full backup, restore and reset on a real temporary data folder.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/core/storage/backup.dart';
import 'package:smart_clicker/core/storage/zip.dart';

void main() {
  late Directory dir;
  String p(String rel) => '${dir.path}/$rel';
  void put(String rel, String text) => File(p(rel))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(text);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('backup_test');
    put('scripts/Один.cks', 'log(1)');
    put('scripts/Папка/Два.cks', 'log(2)');
    put('files/кнопка.png', 'png');
    put('notes/заметка.md', '# привет');
    put('settings.json', '{"a":1}');
    put('answers.json', '{}');
    put('logs/1.log', 'лог');
    put('ocr/model.onnx', 'модель');
    put('чужой.txt', 'не трогать');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('копия: всё, кроме логов, отчётов и моделей; несохранённый текст скриптов', () {
    final zip = makeBackup(dir.path, scripts: {'Один': 'log(1) // правка', 'Папка/Два': 'log(2)'});
    final files = zipDecode(zip);
    expect(files.keys.toSet(), {
      backupManifestName,
      'scripts/Один.cks', 'scripts/Папка/Два.cks', 'files/кнопка.png', 'notes/заметка.md',
      'settings.json', 'answers.json',
    });
    expect(String.fromCharCodes(files['scripts/Один.cks']!), isNot('log(1)'));
    final info = readBackup(zip).info;
    expect((info.scripts, info.pictures, info.notes), (2, 1, 1));
    expect(countData(dir.path).describe(), 'скриптов: 2, картинок: 1, заметок: 1');
    expect(() => readBackup(zipEncode({'a.cks': [1]})), throwsFormatException);
  });

  test('восстановление заменяет данные, чужое и модели остаются; опасные пути пропускаются', () {
    final zip = makeBackup(dir.path);
    put('scripts/Новый.cks', 'появился после копии');
    File(p('settings.json')).writeAsStringSync('{"a":2}');
    final files = readBackup(zip).files
      ..['../вне.txt'] = Uint8List.fromList([1])
      ..['чужой.txt'] = Uint8List.fromList([2]);
    restoreBackup(dir.path, files);
    expect(File(p('scripts/Новый.cks')).existsSync(), isFalse);
    expect(File(p('scripts/Папка/Два.cks')).readAsStringSync(), 'log(2)');
    expect(File(p('settings.json')).readAsStringSync(), '{"a":1}');
    expect(File(p('чужой.txt')).readAsStringSync(), 'не трогать');
    expect(File(p('ocr/model.onnx')).existsSync(), isTrue);
    expect(File('${dir.parent.path}/вне.txt').existsSync(), isFalse);
  });

  test('сброс удаляет всё своё, кроме моделей OCR', () {
    resetData(dir.path);
    expect(Directory(p('scripts')).existsSync(), isFalse);
    expect(File(p('settings.json')).existsSync(), isFalse);
    expect(Directory(p('logs')).existsSync(), isFalse);
    expect(File(p('ocr/model.onnx')).existsSync(), isTrue);
    expect(File(p('чужой.txt')).existsSync(), isTrue);
  });
}
