import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/platform/windows/single_instance.dart';

void main() {
  test('вторая копия программы не запускается', () {
    final name = 'Local\\SmartClicker.Test.$pid';
    expect(SingleInstance.acquire(name: name), isTrue);
    // The mutex exists: another copy is running.
    expect(SingleInstance.acquire(name: name), isFalse);
    final sw = Stopwatch()..start();
    expect(SingleInstance.acquire(name: name, waitMs: 300), isFalse);
    expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(250));
    SingleInstance.release();
    expect(SingleInstance.acquire(name: name), isTrue);
    SingleInstance.release();
  }, skip: !Platform.isWindows);
}
