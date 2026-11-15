// Live check of the clipboard on real Windows: change number, files,
// picture and text are written and read back; the text that was in the
// clipboard before is put back at the end. Run: dart run tool/smoke_clipboard.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:smart_clicker/platform/windows/windows_backend.dart';

void main() {
  final b = WindowsBackend();
  final before = b.getClipboard();
  var ok = true;
  void check(bool cond, String what) {
    stdout.writeln('${cond ? 'OK  ' : 'FAIL'} $what');
    if (!cond) ok = false;
  }

  final s0 = b.clipboardSequence();
  final files = [Platform.resolvedExecutable, '${Directory.systemTemp.path}\\нет такого файла.txt'];
  check(b.setClipboardFiles(files), 'файлы положены в буфер');
  check(b.clipboardSequence() != s0, 'номер изменения буфера вырос');
  final f = b.readClipboard();
  check(f?.files?.length == 2 && f!.files![1].endsWith('нет такого файла.txt'), 'файлы прочитаны: ${f?.files}');

  final px = Uint8List.fromList([
    0, 0, 255, 255, 0, 255, 0, 255, //
    255, 0, 0, 255, 10, 20, 30, 255,
  ]);
  check(b.setClipboardImage(2, 2, px), 'картинка положена в буфер');
  final img = b.readClipboard()?.image;
  check(img != null && img.w == 2 && img.h == 2, 'картинка прочитана: ${img?.w}x${img?.h}');
  if (img != null) {
    check(img.bgra[2] == 255 && img.bgra[8] == 255 && img.bgra[14] == 30,
        'пиксели на своих местах (верхний ряд сверху)');
  }

  b.setClipboard('проверка буфера SmartClicker');
  check(b.readClipboard()?.text == 'проверка буфера SmartClicker', 'текст прочитан');
  check(b.readClipboard()?.private == false, 'обычный текст не помечен как пароль');

  b.setClipboard(before);
  stdout.writeln('буфер возвращён: ${before.length} символов');
  exit(ok ? 0 : 1);
}
