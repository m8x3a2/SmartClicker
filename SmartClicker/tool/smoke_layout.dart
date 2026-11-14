// ignore_for_file: avoid_print
// Isolated Notepad matrix: installed EN/RU layouts and Caps Lock transitions.
// Leaves the unique test document open; restores layout, Caps parity and text clipboard.
// Usage: dart run tool/smoke_layout.dart [rounds] [stress|longline]
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:smart_clicker/core/engine/runtime.dart';
import 'package:smart_clicker/platform/backend.dart';

import 'smoke_type.dart' show SmokeBackend;

final user32 = DynamicLibrary.open('user32.dll');
final layouts = user32
    .lookupFunction<
      Int32 Function(Int32, Pointer<IntPtr>),
      int Function(int, Pointer<IntPtr>)
    >('GetKeyboardLayoutList');
final layout = user32
    .lookupFunction<IntPtr Function(Uint32), int Function(int)>(
      'GetKeyboardLayout',
    );
final guiInfo = user32
    .lookupFunction<
      Int32 Function(Uint32, Pointer<Uint8>),
      int Function(int, Pointer<Uint8>)
    >('GetGUIThreadInfo');
final post = user32
    .lookupFunction<
      Int32 Function(IntPtr, Uint32, IntPtr, IntPtr),
      int Function(int, int, int, int)
    >('PostMessageW');

class MatrixBackend extends SmokeBackend {
  MatrixBackend(super.document);
  int toggles = 0;
  int chars = 0;
  bool toggleDuringType = false;
  void Function(int)? onCharacter;
  @override
  void keyEvent(String key, bool down) {
    super.keyEvent(key, down);
    if (key == 'capslock' && down) toggles++;
  }

  @override
  void typeText(String text, {TypeMethod method = TypeMethod.auto}) {
    onCharacter?.call(chars);
    if (toggleDuringType && (chars == 8 || chars == 24)) {
      keyEvent('capslock', true);
      keyEvent('capslock', false);
    }
    chars++;
    super.typeText(text, method: method);
  }
}

Future<void> main(List<String> args) async {
  final rounds = args.isEmpty ? 2 : int.parse(args[0]);
  final longLine = args.length > 1 && args[1] == 'longline';
  final stress = longLine || (args.length > 1 && args[1] == 'stress');
  final dir = await Directory.systemTemp.createTemp('smartclicker-layout-');
  final name = 'layout-${DateTime.now().microsecondsSinceEpoch}.txt';
  final file = File('${dir.path}/$name');
  await file.writeAsString('');
  final b = MatrixBackend(name);
  final cover = b.activeWindow();
  final clipboard = b.getClipboard();
  await Process.start('notepad.exe', [
    file.path,
  ], mode: ProcessStartMode.detached);
  for (var i = 0; i < 100 && b.target == null; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    b.target = b.windows().where(b.owns).firstOrNull?.handle;
  }
  if (b.target == null) throw StateError('Тестовый документ не открылся');
  b.focusWindow(b.target!);
  await Future<void>.delayed(const Duration(milliseconds: 300));
  b.check();
  final originalLayout = layout(b.inputThreads().focus);
  Future<void> selectLayout(int hkl) async {
    b.check();
    final info = calloc<Uint8>(72);
    try {
      final d = ByteData.sublistView(info.asTypedList(72));
      d.setUint32(0, 72, Endian.little);
      if (guiInfo(0, info) == 0) throw StateError('Нет данных о фокусе');
      final focus = d.getInt64(16, Endian.little);
      if (focus == 0 || post(focus, 0x50, 0, hkl) == 0) {
        throw StateError('Не удалось запросить раскладку');
      }
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (layout(b.inputThreads().focus) == hkl) return;
      }
      throw StateError(
        'Раскладка не переключилась на ${hkl.toRadixString(16)}',
      );
    } finally {
      calloc.free(info);
    }
  }

  Future<String> run(String source) async {
    var result = '';
    final rt = ScriptRuntime(b, {'main': 'matrix', 'source': source}, (e) {
      if (e['t'] == 'log' && e['lv'] == 'info') result = '${e['m']}';
    });
    final r = await rt.runMain();
    if (r['error'] != null) throw StateError('${r['error']}');
    return result;
  }

  Future<String> probe() async {
    b.setClipboard('probe-pending');
    return run('''
with_window("notepad") {
  key("ctrl+a")
  key("delete")
  click(50%, 50%)
  key("a")
  wait(200)
  key("ctrl+a")
  key("ctrl+c")
}
wait(300)
log(get_clipboard())
''');
  }

  final list = calloc<IntPtr>(32);
  final count = layouts(32, list);
  final installed = [for (var i = 0; i < count; i++) list[i]];
  calloc.free(list);
  var passed = 0, total = 0;
  const text = 'aAzZ ёЁ Привет Hello 1234567890 !@# Яя 😀';
  final originalProbe = await probe();
  try {
    if (stress) {
      final en = installed.firstWhere((v) => (v & 0xFFFF) == 0x409);
      final ru = installed.firstWhere((v) => (v & 0xFFFF) == 0x419);
      const segment = 'AbЯя ёЁ Hello 1234567890 !@#"№;:? /\\ 😀\n';
      for (final scenario in longLine ? ['long-line-switch'] : ['switch', 'long-switch', 'long']) {
        final expected = List.filled(
          longLine ? 52 : (scenario == 'switch' ? 3 : 16),
          longLine ? segment.replaceAll('\n', ' ') : segment,
        ).join();
        for (var round = 0; round < rounds; round++) {
          await selectLayout(en);
          b.chars = 0;
          var changes = 0;
          Object? switchError;
          final pending = <Future<void>>[];
          b.onCharacter = (index) {
            if (scenario == 'long' || index == 0 || index % 37 != 0) return;
            final next = changes.isEven ? ru : en;
            changes++;
            pending.add(
              selectLayout(next).catchError((Object error) {
                switchError = error;
              }),
            );
          };
          b.setClipboard('stress-pending');
          final got = await run('''
with_window("notepad") {
  key("ctrl+a")
  key("delete")
  click(50%, 50%)
  type(${jsonEncode(expected)})
  wait(500)
  key("ctrl+a")
  key("ctrl+c")
  key("end")
}
wait(300)
log(get_clipboard())
''');
          b.onCharacter = null;
          await Future.wait(pending);
          if (switchError != null) throw StateError('$switchError');
          final normalized = got.replaceAll('\r', '');
          final same = normalized == expected;
          total++;
          if (same) passed++;
          print(
            '${same ? 'OK' : 'FAIL'} $scenario: ${expected.runes.length} символов, $changes смен раскладки',
          );
          if (!same) {
            var at = 0;
            while (at < normalized.length &&
                at < expected.length &&
                normalized[at] == expected[at]) {
              at++;
            }
            print(
              'Первое отличие $at; ожидалось ${jsonEncode(expected.substring(at).split('\n').first)}; получено ${jsonEncode(normalized.substring(at).split('\n').first)}',
            );
          }
        }
      }
    } else {
      for (final language in [0x409, 0x419]) {
        final hkl = installed
            .where((v) => (v & 0xFFFF) == language)
            .firstOrNull;
        if (hkl == null) {
          throw StateError(
            'Раскладка ${language.toRadixString(16)} не установлена',
          );
        }
        await selectLayout(hkl);
        for (final mode in ['off', 'on', 'during', 'script']) {
          for (var round = 0; round < rounds; round++) {
            final wanted = mode == 'on' ? 1 : 0;
            final lower = language == 0x409 ? 'a' : 'ф';
            var observed = await probe();
            if (observed.toLowerCase() != lower) {
              throw StateError(
                'Раскладка поля не совпала с HKL: $observed; ${b.layoutDebug()}',
              );
            }
            if ((observed == lower ? 0 : 1) != wanted) {
              await run('key("capslock")\nwait(150)');
            }
            observed = await probe();
            if (observed != (wanted == 0 ? lower : lower.toUpperCase())) {
              throw StateError('Caps Lock не переключился: $observed');
            }
            b.chars = 0;
            b.toggleDuringType = mode == 'during';
            b.setClipboard('matrix-pending');
            final input = mode == 'script'
                ? 'type(${jsonEncode(text.substring(0, 8))})\n'
                      'key("capslock")\n'
                      'type(${jsonEncode(text.substring(8, 24))})\n'
                      'key("capslock")\n'
                      'type(${jsonEncode(text.substring(24))})'
                : 'type(${jsonEncode(text)})';
            final got = await run('''
with_window("notepad") {
  key("ctrl+a")
  key("delete")
  click(50%, 50%)
  $input
  wait(400)
  key("ctrl+a")
  key("ctrl+c")
  key("end")
}
wait(300)
log(get_clipboard())
''');
            b.toggleDuringType = false;
            total++;
            final same = got.replaceAll('\r', '') == text;
            if (same) passed++;
            print(
              '${same ? 'OK' : 'FAIL'} ${language == 0x409 ? 'EN' : 'RU'} Caps=$mode: ${jsonEncode(got)}',
            );
          }
        }
      }
    }
  } finally {
    b.onCharacter = null;
    b.toggleDuringType = false;
    try {
      // Caps Lock is global; undo only toggles injected by this test.
      if (b.toggles.isOdd) {
        b.focusWindow(b.target!);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        b.keyEvent('capslock', true);
        b.keyEvent('capslock', false);
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      await selectLayout(originalLayout);
      final restored = await probe();
      if (restored != originalProbe) {
        throw StateError(
          'Не совпало исходное состояние клавиатуры: $originalProbe → $restored',
        );
      }
      print('Исходная раскладка и Caps Lock восстановлены и проверены');
    } finally {
      b.setClipboard(clipboard);
      if (cover != null) b.focusWindow(cover.handle);
    }
    print('Итог: $passed из $total; документ: ${file.path}');
  }
  exitCode = passed == total ? 0 : 1;
}
