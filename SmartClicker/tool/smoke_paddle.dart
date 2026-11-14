// Checks PaddleOCR on the real screen and compares it with the Windows OCR.
//   dart run tool/smoke_paddle.dart <dir with dll + models> [x y w h]
// ignore_for_file: avoid_print
import 'package:smart_clicker/core/vision/image.dart';
import 'package:smart_clicker/core/vision/paddle_ocr.dart';
import 'package:smart_clicker/platform/windows/windows_backend.dart';

void main(List<String> args) {
  final b = WindowsBackend();
  final r = args.length == 5
      ? args.skip(1).map(int.parse).toList()
      : [0, 0, b.screenSize().w, 300];
  final sw = Stopwatch()..start();
  final ocr = PaddleOcr.open(args[0]);
  print('load ${sw.elapsedMilliseconds} ms');
  for (var i = 0; i < 2; i++) {
    sw.reset();
    final img = Bitmap(r[2], r[3], b.capture(r[0], r[1], r[2], r[3]));
    final lines = ocr.lines(img);
    print('--- paddle ${sw.elapsedMilliseconds} ms, ${lines.length} lines');
    if (i == 0) {
      for (final l in lines) {
        print('${l.confidence.toStringAsFixed(2)} [${l.x},${l.y} ${l.w}x${l.h}] ${l.text}');
      }
    }
  }
  sw.reset();
  final win = b.readText(r[0], r[1], r[2], r[3]);
  print('--- windows ${sw.elapsedMilliseconds} ms\n$win');
}
