// Tools for a neural network: «Настройки от ИИ» (a JSON patch shown as
// changes) and `--check "Скрипт"` (mistakes without running).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/app/services/script_check.dart';
import 'package:smart_clicker/core/storage/settings_patch.dart';
import 'package:smart_clicker/core/storage/storage.dart';

void main() {
  test('каждый ключ для нейросети есть в settings.json', () {
    final json = Settings().toJson();
    for (final k in settingLabels.keys) {
      expect(json.containsKey(k), isTrue, reason: k);
    }
    expect(settingsKeysText(Settings()), contains('runDelaySec — Отсчёт перед запуском, с (сейчас 2)'));
  });

  test('заплатка: изменения, пропуски, ```json```', () {
    final s = Settings();
    final p = settingsPatch(s, '```json\n{"runDelaySec": 5, "showClicks": true, "stopKey": "f12", '
        '"miniX": 10, "nope": 1, "maxLoops": "много", "allowPower": true}\n```');
    expect(p.error, isNull);
    expect({for (final c in p.changes) c.key: c.after}, {'runDelaySec': 5, 'showClicks': true, 'allowPower': true});
    expect(p.changes.firstWhere((c) => c.key == 'allowPower').risky, isTrue);
    expect(p.skipped.keys, containsAll(['miniX', 'nope', 'maxLoops']));
    expect(p.skipped.containsKey('stopKey'), isFalse); // the same value: nothing to do
    expect(p.result!.runDelaySec, 5);
    expect(s.runDelaySec, 2); // the current settings stay as they are
  });

  test('заплатка: не JSON и не объект — понятная ошибка; движок распознавания', () {
    expect(settingsPatch(Settings(), 'сделай побыстрее').error, contains('не JSON'));
    expect(settingsPatch(Settings(), '[1, 2]').error, contains('фигурных'));
    final p = settingsPatch(Settings(), '{"ocrEngine": "windows"}');
    expect(p.changes.single.after, 'windows');
    expect(p.result!.ocrEngine, 'windows');
  });

  test('--check: ошибки без запуска, файл и текст', () {
    final tmp = Directory.systemTemp.createTempSync('sc_check_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final paths = AppPaths(tmp.path);
    final store = ScriptStore(paths.scripts);
    Directory(paths.scripts).createSync(recursive: true);
    store.write('Папка/Хороший', 'click(1, 2)\nwait(1s)\n');
    store.write('Плохой', 'click(1, 2)\nclik(3, 4)\nclick_image("нет такой")\n');

    expect(checkTarget(['--check', 'Плохой']), 'Плохой');
    expect(checkTarget(['--run', 'x']), isNull);

    final good = checkReport(paths, 'Хороший'); // the short name is found too
    expect(good['script'], 'Папка/Хороший');
    expect(good['ok'], isTrue);
    expect(checkText(good), contains('ошибок не найдено'));

    final bad = checkReport(paths, 'Плохой');
    expect(bad['ok'], isFalse);
    final lines = [for (final i in bad['issues'] as List) (i as Map)['line']];
    expect(lines, containsAll([2, 3]));

    expect(checkReport(paths, 'Нет')['found'], isFalse);

    expect(runCheckCommand(paths, 'Плохой'), 1);
    final file = jsonDecode(File('${paths.files}${Platform.pathSeparator}check.json').readAsStringSync());
    expect(file['script'], 'Плохой');
  });
}
