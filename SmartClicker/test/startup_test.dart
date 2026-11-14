// Start with Windows: reading the logon entry, the command, the setting and
// the line on the "Access" screen.
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/core/storage/storage.dart';
import 'package:smart_clicker/core/system/access.dart';
import 'package:smart_clicker/core/system/startup.dart';
import 'package:smart_clicker/platform/stub_backend.dart';

void main() {
  const exe = r'C:\Program Files\SmartClicker\smart_clicker.exe';

  test('команда автозагрузки: путь в кавычках и признак запуска с Windows', () {
    expect(startupCommand(exe), '"$exe" --autostart');
  });

  test('что значит запись автозагрузки', () {
    expect(describeStartup(null, disabled: false, exe: exe).active, isFalse);

    var i = describeStartup(startupCommand(exe), disabled: false, exe: exe);
    expect(i.active, isTrue);
    expect(i.otherPath, isNull);

    // Case of the path does not matter on Windows.
    i = describeStartup(startupCommand(exe.toUpperCase()), disabled: false, exe: exe);
    expect(i.active, isTrue);

    // Turned off in Task Manager.
    i = describeStartup(startupCommand(exe), disabled: true, exe: exe);
    expect(i.on, isFalse);
    expect(i.disabled, isTrue);
    expect(i.active, isFalse);

    // Another copy (the program was moved, or a debug build).
    i = describeStartup(r'"D:\old\smart_clicker.exe" --autostart', disabled: false, exe: exe);
    expect(i.on, isTrue);
    expect(i.ours, isFalse);
    expect(i.otherPath, r'D:\old\smart_clicker.exe');

    i = describeStartup(r'D:\old\smart_clicker.exe --autostart', disabled: false, exe: exe);
    expect(i.otherPath, r'D:\old\smart_clicker.exe');
  });

  test('заглушка: включение снова разрешает выключенную в Диспетчере запись', () {
    final b = StubBackend()
      ..startupCommand = startupCommand(exe)
      ..startupDisabled = true;
    expect(b.startupEntry().disabled, isTrue);
    b.setStartupEntry(startupCommand(exe));
    expect(b.startupEntry().disabled, isFalse);
    b.setStartupEntry(null);
    expect(b.startupEntry().command, isNull);
  });

  test('настройка «сразу в трей» и строка в «Доступах»', () {
    final s = Settings()..autostartTray = false;
    expect(Settings.fromJson(s.toJson()).autostartTray, isFalse);
    expect(Settings.fromJson({}).autostartTray, isTrue);
    expect(settingsGroups['startup'], ['autostartTray']);

    List<AccessItem> items(bool on) => accessItems(AccessFacts(
        elevated: false, paddle: true, allowPower: false, dataDir: 'x', startsWithWindows: on));
    final off = items(false).firstWhere((i) => i.action == 'startup');
    expect(off.actionLabel, 'Включить');
    final on = items(true).firstWhere((i) => i.action == 'startup');
    expect(on.actionLabel, 'Выключить');
  });
}
