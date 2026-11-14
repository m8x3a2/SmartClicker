// The data folder: which one is used at start, and moving / copying the data
// to another folder (on real temporary folders).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/core/storage/storage.dart';
import 'package:smart_clicker/app/ui/settings/data_folder.dart' show sizeText;

void main() {
  late Directory tmp;
  late String standard, exe, other;
  String p(String a, String b) => '$a${Platform.pathSeparator}$b';

  void makeData(String dir, {String script = 'click(1, 2)'}) {
    Directory(p(dir, 'scripts')).createSync(recursive: true);
    File(p(p(dir, 'scripts'), 'Ферма.cks')).writeAsStringSync(script);
    Directory(p(dir, 'files')).createSync(recursive: true);
    File(p(p(dir, 'files'), 'кнопка.png')).writeAsBytesSync(List.filled(100, 7));
    File(p(dir, 'settings.json')).writeAsStringSync('{"stopKey":"f12"}');
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sc_data_');
    standard = p(tmp.path, 'appdata');
    exe = p(tmp.path, 'program');
    other = p(tmp.path, 'other');
    Directory(standard).createSync();
    Directory(exe).createSync();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('какая папка берётся при запуске', () {
    var loc = resolveDataLocation(standard: standard, exeDir: exe);
    expect(loc.dir, standard);
    expect(loc.kind, DataKind.standard);

    // Chosen in the settings.
    Directory(other).createSync();
    writeLocation(standard, other);
    loc = resolveDataLocation(standard: standard, exeDir: exe);
    expect(loc.dir, other);
    expect(loc.kind, DataKind.chosen);

    // The chosen folder is gone (a flash drive pulled out): standard + warning.
    Directory(other).deleteSync();
    loc = resolveDataLocation(standard: standard, exeDir: exe);
    expect(loc.dir, standard);
    expect(loc.unreachable, other);

    // "userdata" next to the program wins over everything.
    Directory(portableDir(exe)).createSync();
    loc = resolveDataLocation(standard: standard, exeDir: exe);
    expect(loc.kind, DataKind.portable);

    // Choosing the standard folder forgets the choice.
    writeLocation(standard, standard);
    expect(readLocation(standard), isNull);
  });

  test('перенос: всё скопировано, старое удалено, чужие файлы не тронуты', () {
    makeData(standard);
    File(p(standard, 'чужой.txt')).writeAsStringSync('не наше');
    final before = measureData(standard);

    final err = changeDataFolder(
        from: standard, to: other, mode: DataMove.move, standard: standard, exeDir: exe);
    expect(err, isNull);
    expect(measureData(other).files, before.files);
    expect(measureData(other).bytes, before.bytes);
    expect(File(p(p(other, 'scripts'), 'Ферма.cks')).readAsStringSync(), 'click(1, 2)');
    expect(looksLikeData(standard), isFalse);
    expect(File(p(standard, 'чужой.txt')).existsSync(), isTrue);
    expect(readLocation(standard), other);
    expect(resolveDataLocation(standard: standard, exeDir: exe).dir, other);

    // And back to the standard folder.
    expect(
        changeDataFolder(from: other, to: standard, mode: DataMove.move, standard: standard, exeDir: exe),
        isNull);
    expect(looksLikeData(standard), isTrue);
    expect(readLocation(standard), isNull);
  });

  test('копия и «начать заново» не трогают старые данные', () {
    makeData(standard);
    expect(changeDataFolder(from: standard, to: other, mode: DataMove.copy, standard: standard, exeDir: exe),
        isNull);
    expect(looksLikeData(standard), isTrue);
    expect(looksLikeData(other), isTrue);

    final fresh = p(tmp.path, 'fresh');
    expect(changeDataFolder(from: other, to: fresh, mode: DataMove.fresh, standard: standard, exeDir: exe),
        isNull);
    expect(looksLikeData(other), isTrue);
    expect(measureData(fresh).files, 0);
    expect(readLocation(standard), fresh);
  });

  test('нельзя: та же папка, внутрь текущей, поверх чужих данных', () {
    makeData(standard);
    expect(changeDataFolder(from: standard, to: standard, mode: DataMove.move, standard: standard, exeDir: exe),
        isNotNull);
    expect(
        changeDataFolder(
            from: standard, to: p(standard, 'inner'), mode: DataMove.move, standard: standard, exeDir: exe),
        isNotNull);
    makeData(other, script: 'другой');
    expect(changeDataFolder(from: standard, to: other, mode: DataMove.copy, standard: standard, exeDir: exe),
        isNotNull);
    // Nothing was overwritten.
    expect(File(p(p(other, 'scripts'), 'Ферма.cks')).readAsStringSync(), 'другой');
    // "Use what is there" is fine.
    expect(changeDataFolder(from: standard, to: other, mode: DataMove.use, standard: standard, exeDir: exe),
        isNull);
    expect(readLocation(standard), other);
  });

  test('выбранная папка с чужими файлами: данные кладутся в подпапку SmartClicker', () {
    Directory(other).createSync();
    expect(dataDirFor(other), other); // empty
    File(p(other, 'фото.jpg')).writeAsStringSync('x');
    expect(dataDirFor(other), p(other, 'SmartClicker'));
    makeData(p(tmp.path, 'data2'));
    expect(dataDirFor(p(tmp.path, 'data2')), p(tmp.path, 'data2')); // already SmartClicker's
    expect(scriptCount(p(tmp.path, 'data2')), 1);
  });

  test('размер данных словами', () {
    expect(sizeText(0), '0 КБ');
    expect(sizeText(1500), '2 КБ');
    expect(sizeText(5 * 1048576), '5.0 МБ');
    expect(sizeText(3 * 1073741824), '3.0 ГБ');
  });

  test('флешка: перенос рядом с программой и обратно', () {
    makeData(standard);
    final portable = portableDir(exe);
    expect(changeDataFolder(from: standard, to: portable, mode: DataMove.move, standard: standard, exeDir: exe),
        isNull);
    expect(readLocation(standard), isNull);
    expect(resolveDataLocation(standard: standard, exeDir: exe).kind, DataKind.portable);

    // Copy away: the folder next to the program must stop winning.
    expect(changeDataFolder(from: portable, to: other, mode: DataMove.copy, standard: standard, exeDir: exe),
        isNull);
    expect(Directory(portable).existsSync(), isFalse);
    expect(Directory('$portable (не используется)').existsSync(), isTrue);
    expect(resolveDataLocation(standard: standard, exeDir: exe).dir, other);
  });
}
