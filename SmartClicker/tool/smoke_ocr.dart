// Checks the real Windows OCR: reads the top strip of the screen.
//   dart run tool/smoke_ocr.dart [x y w h]
// ignore_for_file: avoid_print
import 'package:smart_clicker/platform/windows/ocr.dart';
import 'package:smart_clicker/platform/windows/windows_backend.dart';

void main(List<String> args) {
  final b = WindowsBackend();
  print('languages: ${ocrLanguages()}');
  final r = args.length == 4
      ? args.map(int.parse).toList()
      : [0, 0, b.screenSize().w, 300];
  for (var i = 0; i < 3; i++) {
    final sw = Stopwatch()..start();
    final text = b.readText(r[0], r[1], r[2], r[3]);
    print('--- ${sw.elapsedMilliseconds} ms');
    if (i == 0) print(text);
  }
  final sw = Stopwatch()..start();
  print('small: "${b.readText(r[0], r[1], 400, 40)}" ${sw.elapsedMilliseconds} ms');
}
