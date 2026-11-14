// Downloads PaddleOCR into a folder (checks the URLs and checksums).
//   dart run tool/smoke_install.dart <dir>
// ignore_for_file: avoid_print
import 'package:smart_clicker/app/services/ocr_install.dart';
import 'package:smart_clicker/core/vision/paddle_ocr.dart';

Future<void> main(List<String> args) async {
  var last = -1;
  final sw = Stopwatch()..start();
  await installPaddle(args[0], (done, file) {
    final pc = (done * 10).floor();
    if (pc != last) {
      last = pc;
      print('${pc * 10}% $file');
    }
  });
  print('done in ${sw.elapsed.inSeconds}s, missing: ${PaddleOcr.missing(args[0])}');
}
