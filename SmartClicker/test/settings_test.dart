import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/app/state/app_controller.dart' show formatDuration;
import 'package:smart_clicker/core/storage/storage.dart';

void main() {
  test('группы настроек: каждое имя есть в settings.json, без повторов', () {
    final json = Settings().toJson();
    final all = settingsGroups.values.expand((k) => k).toList();
    expect(all.toSet().length, all.length);
    for (final k in all) {
      expect(json.containsKey(k), isTrue, reason: k);
    }
  });

  test('сброс блока и всех настроек', () {
    final s = Settings()
      ..stopKey = 'f2'
      ..runDelaySec = 9
      ..human = true
      ..scriptKeys = {'Фарм': 'f7'}
      ..breakpoints = {'Фарм': [3]};
    expect(s.isDefault(settingsGroups['hotkeys']!), isFalse);
    final a = s.withDefaults(settingsGroups['hotkeys']!);
    expect((a.stopKey, a.runDelaySec, a.human), ('f12', 9, true));
    final b = s.withDefaults(settingsGroups.values.expand((k) => k));
    expect((b.stopKey, b.runDelaySec, b.human), ('f12', Settings().runDelaySec, false));
    expect(b.isDefault(settingsGroups.values.expand((k) => k)), isTrue);
    // Keys of single scripts and breakpoints stay.
    expect(b.scriptKeys, {'Фарм': 'f7'});
    expect(b.breakpoints, {'Фарм': [3]});
  });

  test('слово для сброса: reset по умолчанию, пустое и длинное не принимаются', () {
    expect(Settings().resetWord, 'reset');
    expect(Settings.fromJson({'resetWord': ' стереть '}).resetWord, 'стереть');
    expect(Settings.fromJson({'resetWord': ''}).resetWord, 'reset');
    expect(Settings.fromJson({'resetWord': 'x' * 31}).resetWord, 'reset');
    expect(settingsGroups['data'], ['resetWord']);
  });

  test('длительность запуска для лога и истории', () {
    expect(formatDuration(4200), '4.2 с');
    expect(formatDuration(200000), '3 мин 20 с');
    expect(formatDuration(3900000), '1 ч 05 мин');
  });
}
