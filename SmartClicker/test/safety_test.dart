// Guard against self-destruction and safe mode: rules, the journal, rescue
// files and the checks inside the engine.

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/core/engine/runtime.dart';
import 'package:smart_clicker/core/storage/settings.dart';
import 'package:smart_clicker/core/system/safety.dart';
import 'package:smart_clicker/platform/stub_backend.dart';

Future<(StubBackend, Map<String, Object?>)> _run(String source,
    {Map<String, Object?> cfg = const {}, int? uptime}) async {
  final b = StubBackend();
  if (uptime != null) b.uptime = uptime;
  final rt = ScriptRuntime(b, {'main': 'test', 'source': source, ...cfg}, (_) {},
      random: Random(1));
  return (b, await rt.runMain());
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('sc_safety_'));
  tearDown(() => tmp.deleteSync(recursive: true));
  String p(String name) => '${tmp.path}${Platform.pathSeparator}$name';

  test('выключение: первые 5 минут и чаще раза в 30 минут — нельзя', () {
    final now = DateTime(2026, 11, 15, 12);
    expect(powerBlockReason(uptimeMs: 60000, recent: const [], now: now), contains('5 минут'));
    expect(powerBlockReason(uptimeMs: 3600000, recent: const [], now: now), isNull);
    expect(
        powerBlockReason(
            uptimeMs: 3600000,
            recent: [now.subtract(const Duration(minutes: 10))],
            now: now),
        contains('30 минут'));
    expect(
        powerBlockReason(
            uptimeMs: 3600000,
            recent: [now.subtract(const Duration(minutes: 40))],
            now: now),
        isNull);
  });

  test('команды выключения и защищённые процессы', () {
    expect(isPowerCommand('shutdown /r /t 0'), isTrue);
    expect(isPowerCommand('C:\\Windows\\System32\\SHUTDOWN.EXE -s'), isTrue);
    expect(isPowerCommand('powershell Restart-Computer -Force'), isTrue);
    expect(isPowerCommand('shutdown /a'), isFalse); // cancels a shutdown
    expect(isPowerCommand('echo hello'), isFalse);
    expect(protectedProcess('Explorer.EXE'), 'explorer');
    expect(protectedProcess('C:\\x\\smart_clicker.exe'), 'smart_clicker');
    expect(protectedProcess('winlogon|Заголовок'), 'winlogon');
    expect(protectedProcess('game.exe'), isNull);
  });

  test('запись: папка данных и программы закрыта, files и другие — можно', () {
    final data = p('data');
    final files = '$data${Platform.pathSeparator}files';
    final exe = p('app');
    String? check(String path) =>
        protectedWrite(path, dataDir: data, filesDir: files, exeDir: exe);
    expect(check('$files${Platform.pathSeparator}a.txt'), isNull);
    expect(check('$data${Platform.pathSeparator}settings.json'), contains('данных'));
    expect(check('$files${Platform.pathSeparator}..${Platform.pathSeparator}settings.json'),
        contains('данных'));
    expect(check('$exe${Platform.pathSeparator}smart_clicker.exe'), contains('программы'));
    expect(check(p('other.txt')), isNull);
  });

  test('петля падений: 3 запуска подряд без нормального выхода за 3 минуты', () {
    final now = DateTime(2026, 11, 15, 12);
    LaunchRecord ago(int sec, {bool clean = false}) =>
        LaunchRecord(now.subtract(Duration(seconds: sec)), clean: clean);
    expect(isCrashLoop([ago(100), ago(60), ago(20)], now), isTrue);
    expect(isCrashLoop([ago(100), ago(60, clean: true), ago(20)], now), isFalse);
    expect(isCrashLoop([ago(400), ago(60), ago(20)], now), isFalse); // too long ago
    expect(isCrashLoop([ago(60), ago(20)], now), isFalse);
  });

  test('журнал защиты сохраняется и переживает испорченный файл', () {
    final path = p('safety.json');
    final j = SafetyJournal(path)
      ..launches.add(LaunchRecord(DateTime(2026, 1, 1), clean: true))
      ..power.add(DateTime(2026, 1, 2));
    j.save();
    final back = SafetyJournal.load(path);
    expect(back.launches.single.clean, isTrue);
    expect(back.power.single, DateTime(2026, 1, 2));
    File(path).writeAsStringSync('{не json');
    expect(SafetyJournal.load(path).launches, isEmpty);
  });

  test('safe.txt и reset.txt: находятся, срабатывают и удаляются', () {
    File(p('safe.txt')).writeAsStringSync('');
    File(p('reset.txt')).writeAsStringSync(' True \n');
    final r = takeRescueFiles([tmp.path]);
    expect(r.safe, isTrue);
    expect(r.reset, isTrue);
    expect(File(p('safe.txt')).existsSync(), isFalse);
    expect(File(p('reset.txt')).existsSync(), isFalse);

    File(p('reset.txt')).writeAsStringSync('потом');
    final r2 = takeRescueFiles([tmp.path]);
    expect(r2.reset, isFalse);
    expect(File(p('reset.txt')).existsSync(), isTrue); // other words: left alone

    File(p('settings.json')).writeAsStringSync('{"stopKey":"q"}');
    final moved = moveAside([p('settings.json'), p('schedule.json')], p('rescue'));
    expect(moved, ['settings.json']);
    expect(File(p('settings.json')).existsSync(), isFalse);
    expect(File('${p('rescue')}${Platform.pathSeparator}settings.json').readAsStringSync(),
        '{"stopKey":"q"}');
  });

  test('настройки: защита включена, задержка 300 с', () {
    final s = Settings();
    expect(s.selfProtect, isTrue);
    expect(s.autostartDelaySec, 300);
    final back = Settings.fromJson({...s.toJson(), 'selfProtect': false, 'autostartDelaySec': 99999});
    expect(back.selfProtect, isFalse);
    expect(back.autostartDelaySec, 3600);
  });

  group('движок', () {
    test('system_power и run_command с shutdown в первые минуты — ошибка', () async {
      final (b, r) = await _run('system_power("restart")',
          cfg: {'allowPower': true}, uptime: 120000);
      expect('${r['error']}', contains('защита от самоуничтожения'));
      expect(b.calls, isNot(contains('power restart')));

      final (_, r2) = await _run('run_command("shutdown /r /t 0")', uptime: 120000);
      expect('${r2['error']}', contains('защита от самоуничтожения'));

      // the guard turned off in the settings
      final (b3, r3) = await _run('system_power("restart")',
          cfg: {'allowPower': true, 'selfProtect': false}, uptime: 120000);
      expect(r3['error'], isNull);
      expect(b3.calls, contains('power restart'));

      // lock is not switching off
      final (_, r4) = await _run('system_power("lock")', uptime: 1000);
      expect(r4['error'], isNull);
    });

    test('второе выключение за 30 минут — ошибка (журнал)', () async {
      final cfg = {'allowPower': true, 'safetyFile': p('safety.json')};
      final (b, r) = await _run('system_power("sleep")', cfg: cfg);
      expect(r['error'], isNull);
      expect(b.calls, contains('power sleep'));
      final (b2, r2) = await _run('system_power("sleep")', cfg: cfg);
      expect('${r2['error']}', contains('30 минут'));
      expect(b2.calls, isNot(contains('power sleep')));
    });

    test('kill_process не закрывает SmartClicker и части Windows', () async {
      final (b, r) = await _run('kill_process("explorer.exe")');
      expect('${r['error']}', contains('часть Windows'));
      expect(b.calls.where((c) => c.contains('explorer')), isEmpty);
      final (_, r2) = await _run('kill_process("smart_clicker")');
      expect('${r2['error']}', contains('сам SmartClicker'));
    });

    test('write_file в папку данных — ошибка, в files — можно', () async {
      final data = p('data');
      final files = '$data${Platform.pathSeparator}files';
      final cfg = {'dataDir': data, 'filesDir': files};
      final (_, r) = await _run('write_file("ok.txt", "1")', cfg: cfg);
      expect(r['error'], isNull);
      expect(File('$files${Platform.pathSeparator}ok.txt').existsSync(), isTrue);
      final target = '$data${Platform.pathSeparator}settings.json'.replaceAll('\\', '/');
      final (_, r2) = await _run('append_file("$target", "x")', cfg: cfg);
      expect('${r2['error']}', contains('папка данных'));
      expect(File('$data${Platform.pathSeparator}settings.json').existsSync(), isFalse);
    });
  });
}
