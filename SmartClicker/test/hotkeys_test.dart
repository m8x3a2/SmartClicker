// Hotkeys held back from other programs: which key of a combo the keyboard
// hook eats, and which hotkeys are held back in each state of the program.
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/app/state/app_controller.dart';
import 'package:smart_clicker/core/storage/storage.dart';
import 'package:smart_clicker/platform/keys.dart';
import 'package:smart_clicker/platform/stub_backend.dart';

void main() {
  test('главная клавиша сочетания и когда нажатие его завершает', () {
    final ctrlAltS = AppController.comboVks('ctrl+alt+s');
    expect(mainKeyOf(ctrlAltS), 0x53);
    expect(mainKeyOf(AppController.comboVks('f12')), 0x7B);
    expect(mainKeyOf(AppController.comboVks('alt+shift')), isNull);

    final down = <int>{};
    bool isDown(int vk) => down.contains(vk);
    expect(completesCombo(0x53, ctrlAltS, isDown), isFalse); // S alone
    down.add(0x11);
    expect(completesCombo(0x53, ctrlAltS, isDown), isFalse); // Ctrl+S
    down.add(0x12);
    expect(completesCombo(0x53, ctrlAltS, isDown), isTrue); // Ctrl+Alt+S
    expect(completesCombo(0x11, ctrlAltS, isDown), isFalse); // modifiers pass
    expect(completesCombo(0x7B, AppController.comboVks('f12'), isDown), isTrue);
  });

  test('перехватываются только клавиши, которые сейчас что-то делают', () {
    final s = Settings()
      ..miniKey = 'f7'
      ..runKey = 'ctrl+f5'
      ..scriptKeys = {'Ферма': 'f4'};
    List<String> held(RunState st, {bool hasScript = true}) =>
        AppControllerHotkeys.heldBackHotkeys(s, st, hasScript: hasScript);

    // Nothing runs: F12 and F8 stay with the active program.
    expect(held(RunState.idle), unorderedEquals(['f9', 'f6', 'f7', 'ctrl+f5', 'f4']));
    expect(held(RunState.idle, hasScript: false), unorderedEquals(['f6', 'f7', 'f4']));

    // Esc (second stop key) stops scripts only: during recording it is a
    // key to record and goes to the program.
    expect(held(RunState.running), unorderedEquals(['f12', 'esc', 'f8', 'f6', 'f7']));
    expect(held(RunState.paused), unorderedEquals(['f12', 'esc', 'f8', 'f6', 'f7']));
    expect(held(RunState.countdown), unorderedEquals(['f12', 'esc', 'f6', 'f7']));
    expect(held(RunState.recording), unorderedEquals(['f12', 'f9', 'f6', 'f7']));

    s.stopKey2 = '';
    expect(held(RunState.running), unorderedEquals(['f12', 'f8', 'f6', 'f7']));

    s.miniKey = '';
    expect(held(RunState.running), isNot(contains('')));

    s.holdBackHotkeys = false;
    expect(held(RunState.running), isEmpty);
  });

  test('только что назначенная клавиша не срабатывает, пока её не отпустят', () {
    final last = <String, bool>{};
    // Assigned in the dialog: the first poll sees it already held.
    expect(AppControllerHotkeys.freshPress(last, 'volume_mute', true), isFalse);
    expect(AppControllerHotkeys.freshPress(last, 'volume_mute', true), isFalse);
    expect(AppControllerHotkeys.freshPress(last, 'volume_mute', false), isFalse);
    expect(AppControllerHotkeys.freshPress(last, 'volume_mute', true), isTrue);
    expect(AppControllerHotkeys.freshPress(last, 'volume_mute', true), isFalse);
  });

  test('во время записи клавиши либо работают в кликере, либо записываются', () {
    final s = Settings()
      ..miniKey = 'f7'
      ..runKey = 'ctrl+f5'
      ..scriptKeys = {'Ферма': 'f4'};
    final rec = AppControllerHotkeys.recordingHotkeys(s);
    expect(rec, unorderedEquals(['f12', 'f9', 'f6', 'f7']));
    // Pause, Esc and keys of scripts do nothing while recording: recorded.
    expect(rec, isNot(contains('f8')));
    expect(rec, isNot(contains('esc')));
    expect(rec, isNot(contains('f4')));
    expect(AppControllerHotkeys.heldBackHotkeys(s, RunState.recording, hasScript: true),
        unorderedEquals(rec));
  });

  test('настройка сохраняется и сбрасывается вместе с горячими клавишами', () {
    final s = Settings()
      ..holdBackHotkeys = false
      ..stopKey2 = '';
    expect(Settings.fromJson(s.toJson()).holdBackHotkeys, isFalse);
    expect(Settings.fromJson(s.toJson()).stopKey2, '');
    expect(Settings.fromJson({}).holdBackHotkeys, isTrue);
    expect(Settings.fromJson({}).stopKey2, 'esc');
    expect(settingsGroups['hotkeys'], containsAll(['holdBackHotkeys', 'stopKey2']));
    expect(Settings().stopKeysLabel, 'F12 / ESC');
    expect(s.stopKeysLabel, 'F12');
  });

  test('заглушка запоминает перехватываемые сочетания', () {
    final b = StubBackend();
    expect(b.holdBackKeys([AppController.comboVks('f12')]), isTrue);
    expect(b.heldBack, [
      [0x7B]
    ]);
    b.stopKeyHook();
    expect(b.heldBack, isEmpty);
  });
}
