// Prints how the elevation check sees this process and the open windows.
// ignore_for_file: avoid_print
import 'package:smart_clicker/platform/windows/windows_backend.dart';

void main() {
  final b = WindowsBackend();
  print('this process elevated: ${b.isProcessElevated(b.ownPid)}');
  final seen = <int>{};
  for (final w in b.windows()) {
    if (!seen.add(w.pid)) continue;
    print('${w.process.padRight(28)} elevated: ${b.isProcessElevated(w.pid)}');
  }
  print('ocr languages: ${b.ocrLanguages()}');
}
