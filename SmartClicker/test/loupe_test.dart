// The magnifier of a pick and the keys held back while picking.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/app/state/app_controller.dart';
import 'package:smart_clicker/core/storage/storage.dart';
import 'package:smart_clicker/core/vision/bitmap.dart';
import 'package:smart_clicker/core/vision/loupe.dart';

/// 20×20 picture: pixel (x, y) has blue = x, green = y, red = 200.
Bitmap _grid() {
  final px = Uint8List(20 * 20 * 4);
  for (var y = 0; y < 20; y++) {
    for (var x = 0; x < 20; x++) {
      final i = (y * 20 + x) * 4;
      px[i] = x;
      px[i + 1] = y;
      px[i + 2] = 200;
    }
  }
  return Bitmap(20, 20, px);
}

List<int> _at(Bitmap b, int x, int y) {
  final i = (y * b.w + x) * 4;
  return [b.bgra[i], b.bgra[i + 1], b.bgra[i + 2], b.bgra[i + 3]];
}

void main() {
  test('loupe enlarges the pixels around the point and frames the centre', () {
    final img = loupeImage(_grid(), 10, 10, cells: 5, cell: 4);
    expect(img.w, 5 * 4 + 2);
    expect(img.h, 5 * 4 + 2);
    // opaque everywhere
    for (var i = 3; i < img.bgra.length; i += 4) {
      expect(img.bgra[i], 255);
    }
    // cell (0, 0) is pixel (8, 8); inside the cell (not on the faint grid)
    expect(_at(img, 1 + 2, 1 + 2), [8, 8, 200, 255]);
    // cell (4, 1) is pixel (12, 9)
    expect(_at(img, 1 + 4 * 4 + 2, 1 + 4 + 2), [12, 9, 200, 255]);
    // the centre cell: black frame inside a white one
    final c0 = 1 + 2 * 4;
    expect(_at(img, c0, c0), [0, 0, 0, 255]);
    expect(_at(img, c0 - 1, c0 - 1), [255, 255, 255, 255]);
    // and its middle shows the pixel itself
    expect(_at(img, c0 + 2, c0 + 2), [10, 10, 200, 255]);
  });

  test('loupe near the edge shows dark grey outside the picture', () {
    final img = loupeImage(_grid(), 0, 0, cells: 5, cell: 4);
    expect(_at(img, 1 + 2, 1 + 2), [0x23, 0x1F, 0x1B, 255]); // pixel (-2, -2)
    expect(_at(img, 1 + 4 * 4 + 2, 1 + 4 * 4 + 2), [2, 2, 200, 255]); // pixel (2, 2)
  });

  test('pipette copies the colour and the point in px and percent', () {
    expect(AppControllerPick.colorPickText(const CursorInfo(835, 521, 43.4896, 48.2407, 0xE5E6E6)),
        '#E5E6E6   835, 521 px   43.49%, 48.24%');
  });

  test('Esc is held back while picking, other hotkeys stay', () {
    final s = Settings();
    final idle = AppControllerHotkeys.heldBackHotkeys(s, RunState.idle, hasScript: true);
    final picking =
        AppControllerHotkeys.heldBackHotkeys(s, RunState.idle, hasScript: true, picking: true);
    expect(idle, isNot(contains('esc')));
    expect(picking, ['esc', ...idle]);
    s.holdBackHotkeys = false;
    expect(AppControllerHotkeys.heldBackHotkeys(s, RunState.idle, hasScript: true, picking: true),
        ['esc']);
  });
}
