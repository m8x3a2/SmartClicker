// ignore_for_file: avoid_print
// Shows the click marker for 3 seconds at a given point (visual check).
// Run: dart run tool/smoke_marker.dart 300 300
import 'dart:io';

import 'package:smart_clicker/platform/backend.dart';

Future<void> main(List<String> args) async {
  final b = createBackend();
  final x = int.parse(args[0]), y = int.parse(args[1]);
  b.showMarker(x, y);
  print('shown at $x,$y');
  await Future<void>.delayed(const Duration(seconds: 3));
  b.hideMarker();
  print('hidden');
  exit(0);
}
