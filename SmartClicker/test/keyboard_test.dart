// type(method:), paste() giving the user's clipboard back, beep() and sound().

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/core/engine/runtime.dart';
import 'package:smart_clicker/platform/stub_backend.dart';

Future<Map<String, Object?>> go(StubBackend b, String source, {String? files}) =>
    ScriptRuntime(b, {'main': 't', 'source': source, 'typeDelay': 0, 'filesDir': ?files}, (_) {},
            random: Random(1))
        .runMain();

void main() {
  test('type: method "auto", "keys", "unicode" и set_option("type_method")', () async {
    final b = StubBackend();
    final r = await go(b, '''
type("ab")
type("cd", method: "keys")
type("ef", method: "unicode")
set_option("type_method", "keys")
type("g")
''');
    expect(r['status'], 'ok', reason: '$r');
    final typed = b.calls.where((c) => c.startsWith('type')).toList();
    // delay 0 (auto) — all at once as Unicode; "keys" always one by one.
    expect(typed, ['type:unicode ab', 'type:keys c', 'type:keys d', 'type:unicode ef', 'type:keys g']);

    final bad = await go(StubBackend(), 'type("a", method: "fast")');
    expect(bad['status'], 'error');
    expect('${bad['error']}', contains('"keys"'));
  });

  test('paste возвращает то, что было в буфере', () async {
    final b = StubBackend()..clipboard = 'моё';
    final r = await go(b, '''
paste("один")
paste("два")
let during = get_clipboard()
wait(700)
log(during, get_clipboard())
''');
    expect(r['status'], 'ok', reason: '$r');
    expect(b.clipboard, 'моё');

    // The script ends right after the paste: the clipboard still comes back.
    final b2 = StubBackend()..clipboard = 'моё';
    await go(b2, 'paste("текст")');
    expect(b2.clipboard, 'моё');

    // restore: false and set_clipboard keep what the script put there.
    final b3 = StubBackend()..clipboard = 'моё';
    await go(b3, 'paste("оставить", restore: false)');
    expect(b3.clipboard, 'оставить');
    final b4 = StubBackend()..clipboard = 'моё';
    await go(b4, 'paste("x")\nset_clipboard("своё")\nwait(700)');
    expect(b4.clipboard, 'своё');
  });

  test('beep и sound', () async {
    final dir = Directory.systemTemp.createTempSync('sc-sound');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}${Platform.pathSeparator}сигнал.wav').writeAsBytesSync([0]);
    final b = StubBackend();
    final r = await go(b, 'beep()\nbeep("error")\nsound("сигнал")\nsound()', files: dir.path);
    expect(r['status'], 'ok', reason: '$r');
    expect(b.calls.where((c) => c.startsWith('beep') || c.startsWith('sound')).toList(), [
      'beep info',
      'beep error',
      'sound ${dir.path}${Platform.pathSeparator}сигнал.wav',
      'sound ',
    ]);
    final missing = await go(StubBackend(), 'sound("нет")', files: dir.path);
    expect('${missing['error']}', contains('нет файла "нет.wav"'));
    final bad = await go(StubBackend(), 'beep("громко")');
    expect(bad['status'], 'error');
  });
}
