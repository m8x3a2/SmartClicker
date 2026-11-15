// Files shared with other programs: read_json, write_json, wait_file,
// export_vars, data.json changed from outside, --run / --stop requests.

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/app/state/app_controller.dart';
import 'package:smart_clicker/core/engine/runtime.dart';
import 'package:smart_clicker/core/storage/storage.dart';
import 'package:smart_clicker/platform/stub_backend.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('sc_files_'));
  tearDown(() => tmp.deleteSync(recursive: true));
  final sep = Platform.pathSeparator;
  String p(String name) => '${tmp.path}$sep$name';

  Future<(List<String>, Map<String, Object?>)> run(String source,
      {void Function()? meanwhile}) async {
    final events = <Map<String, Object?>>[];
    final rt = ScriptRuntime(StubBackend(),
        {'main': 't', 'source': source, 'filesDir': tmp.path, 'dataFile': p('data.json')},
        events.add,
        random: Random(1));
    final done = rt.runMain();
    if (meanwhile != null) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      meanwhile();
    }
    final result = await done;
    return (
      [
        for (final e in events)
          if (e['t'] == 'log' && e['lv'] == 'info') '${e['m']}'
      ],
      result
    );
  }

  test('read_json: весь файл, ключ, вложенный ключ, значение по умолчанию', () async {
    File(p('задание.json')).writeAsStringSync(
        '﻿{"prompt": "Привет", "time": "05:00", "bot": {"names": ["a", "b"]}, "n": 3}');
    final (logs, r) = await run('''
let t = read_json("задание.json")
log(t.prompt, t.n + 1)
log(read_json("задание.json", "time"), read_json("задание.json", "bot.names.1"))
log(read_json("задание.json", "нет", "по умолчанию"), read_json("задание.json", "нет"))
log(read_json("нет такого.json", "a", 7), read_json("нет такого.json"))
''');
    expect(r['error'], isNull, reason: '$r');
    expect(logs, ['Привет 4', '05:00 b', 'по умолчанию null', '7 null']);

    File(p('плохой.json')).writeAsStringSync('{не json');
    final (_, bad) = await run('read_json("плохой.json")');
    expect('${bad['error']}', contains('не JSON'));
  });

  test('write_json: ключ (остальное остаётся), вложенный ключ, весь файл', () async {
    File(p('задание.json')).writeAsStringSync('{"prompt": "Привет", "ready": true}');
    final (_, r) = await run('''
write_json("задание.json", "ready", false)
write_json("задание.json", "result.text", "готово")
write_json("новый.json", {a: 1, b: [1, 2]})
''');
    expect(r['error'], isNull, reason: '$r');
    final t = File(p('задание.json')).readAsStringSync();
    expect(t, contains('"prompt": "Привет"'));
    expect(t, contains('"ready": false'));
    expect(t, contains('"text": "готово"'));
    expect(File(p('новый.json')).readAsStringSync(), contains('"b": ['));
    expect(File(p('задание.json.tmp')).existsSync(), isFalse);
  });

  test('wait_file: изменение файла, ключ со значением, время вышло', () async {
    File(p('задание.json')).writeAsStringSync('{"ready": false}');
    final (logs, r) = await run('''
log(wait_file("задание.json", interval: 50, timeout: 5s))
''', meanwhile: () => File(p('задание.json')).writeAsStringSync('{"ready": false, "x": 1}'));
    expect(r['error'], isNull, reason: '$r');
    expect(logs, ['true']);

    final (logs2, _) = await run('''
log(wait_file("задание.json", key: "ready", value: true, interval: 50, timeout: 5s))
log(read_json("задание.json", "prompt"))
''', meanwhile: () => File(p('задание.json')).writeAsStringSync('{"ready": true, "prompt": "ок"}'));
    expect(logs2, ['true', 'ок']);

    final (logs3, _) = await run('log(wait_file("задание.json", key: "nope", interval: 50, timeout: 200))');
    expect(logs3, ['false']);
  });

  test('export_vars пишет переменные; load_data видит data.json, изменённый снаружи', () async {
    final (logs, r) = await run('''
let kills = 154
let mode = "быстро"
export_vars("состояние.json")
save_data("ход", 1)
wait(600)
log(load_data("ход"))
''', meanwhile: () => File(p('data.json')).writeAsStringSync('{"ход": 25}'));
    expect(r['error'], isNull, reason: '$r');
    final st = File(p('состояние.json')).readAsStringSync();
    expect(st, contains('"kills": 154'));
    expect(st, contains('"mode": "быстро"'));
    expect(st, contains('"script": "t"'));
    expect(logs, ['25']);
  });

  test('--run и --stop: разбор параметров и запрос открытой копии', () {
    expect(requestFromArgs(['--run', 'Папка/Скрипт']), {'run': 'Папка/Скрипт'});
    expect(requestFromArgs(['--stop']), {'stop': true});
    expect(requestFromArgs(['--run']), isNull);
    expect(requestFromArgs(['--autostart']), isNull);
    final paths = AppPaths(tmp.path);
    sendRequest(paths, {'run': 'Бой'});
    final files = Directory(paths.requests).listSync().map((f) => f.path).toList();
    expect(files.single, endsWith('.json'));
    expect(File(files.single).readAsStringSync(), contains('"run":"Бой"'));
  });

  test('настройки: запуск извне и файл состояния выключены', () {
    final s = Settings();
    expect(s.allowExternalRun, isFalse);
    expect(s.stateFile, isFalse);
    final back = Settings.fromJson({...s.toJson(), 'allowExternalRun': true, 'stateFile': true});
    expect(back.allowExternalRun, isTrue);
    expect(back.stateFile, isTrue);
  });
}
