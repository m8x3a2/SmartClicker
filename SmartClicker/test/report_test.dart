import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/core/reports/report.dart';
import 'package:smart_clicker/core/storage/storage.dart';
import 'package:smart_clicker/core/storage/zip.dart';
import 'package:smart_clicker/core/vision/image.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('sc_report'));
  tearDown(() {
    ErrorJournal.path = null;
    tmp.deleteSync(recursive: true);
  });

  test('текст отчёта: ошибка, скрипт с номерами строк, лог, настройки', () {
    final text = reportText(
      time: DateTime(2026, 11, 13, 9, 5, 7),
      script: 'Игры/Ферма',
      status: 'ошибка',
      error: 'Строка 2: нет функции clik',
      scripts: {'Игры/Ферма': 'wait(1)\nclik(5, 5)'},
      log: '09:05:07 [error] ✖ Строка 2',
      settings: {'dryRun': false},
      environment: {'Программа': 'SmartClicker $appVersion'},
      screenshot: true,
    );
    expect(text, contains('Время: 2026-11-13 09:05:07'));
    expect(text, contains('Ошибка: Строка 2: нет функции clik'));
    expect(text, contains('1 | wait(1)\n2 | clik(5, 5)'));
    expect(text, contains('[error]'));
    expect(text, contains('"dryRun": false'));
    expect(text, contains('screen.png'));
    expect(text, isNot(contains('ОШИБКИ САМОЙ ПРОГРАММЫ')));
    expect(numbered(List.filled(12, 'x').join('\n')).split('\n').first, ' 1 | x');
  });

  test('отчёт одним ZIP: текст и снимок экрана', () async {
    final path = '${tmp.path}${Platform.pathSeparator}r.zip';
    final shot = Bitmap(4, 3, Uint8List(4 * 3 * 4)..fillRange(0, 48, 200));
    await saveReport(path, 'ОТЧЁТ\nстрока', shot);
    final files = zipDecode(File(path).readAsBytesSync());
    expect(files.keys, containsAll(['report.txt', 'screen.png']));
    final png = pngDecode(files['screen.png']!);
    expect([png.w, png.h], [4, 3]);
    expect(readReportText(path), 'ОТЧЁТ\nстрока');

    await saveReport(path, 'без снимка', null);
    expect(zipDecode(File(path).readAsBytesSync()).keys, ['report.txt']);
  });

  test('журнал сбоев программы и чистка папки', () {
    final sep = Platform.pathSeparator;
    ErrorJournal.path = '${tmp.path}${sep}logs${sep}app_errors.log';
    expect(ErrorJournal.tail(), '');
    String? seen;
    ErrorJournal.onRecord = (m) => seen = m;
    ErrorJournal.record(StateError('сломалось'), StackTrace.current, where: 'ui');
    ErrorJournal.onRecord = null;
    expect(seen, contains('сломалось'));
    expect(ErrorJournal.tail(), contains('[ui] Bad state: сломалось'));

    for (var i = 0; i < 5; i++) {
      File('${tmp.path}$sep$i.zip').writeAsStringSync('$i');
    }
    pruneFolder(tmp.path, 2);
    final left = tmp.listSync().whereType<File>().map((f) => f.uri.pathSegments.last);
    expect(left.toSet(), {'3.zip', '4.zip'});
  });

  test('настройки справки и отчётов сохраняются', () {
    final s = Settings()
      ..helpCollapsed = true
      ..saveReports = false;
    final back = Settings.fromJson(s.toJson());
    expect(back.helpCollapsed, isTrue);
    expect(back.saveReports, isFalse);
    expect(Settings().saveReports, isTrue);
  });
}
