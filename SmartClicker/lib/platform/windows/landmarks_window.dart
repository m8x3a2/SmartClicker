// Win32 names are kept as-is for readability.
// ignore_for_file: non_constant_identifier_names
// Landmarks: coloured dots on the screen for the eyes only (F4). One
// layered click-through window over all of them, owned by a hidden anchor.
part of 'windows_backend.dart';

mixin _LandmarksWindow implements PlatformBackend {
  int _landmarksWnd = 0;

  /// A hidden popup owned by the main window. The landmarks window is owned
  /// by it: an owned popup is not a second top-level window for Flutter
  /// (the close button keeps working), and unlike a window owned by the
  /// main one directly it is not hidden when the main window is minimized.
  int _anchorWnd = 0;

  int _anchor() {
    if (_anchorWnd != 0) return _anchorWnd;
    final cls = 'Static'.toNativeUtf16();
    final title = ''.toNativeUtf16();
    _anchorWnd = _CreateWindowExW(0x80 /* TOOLWINDOW */, cls, title, 0x80000000 /* POPUP */, 0, 0, 0, 0,
        _findMainWindow(), 0, 0, nullptr);
    calloc.free(cls);
    calloc.free(title);
    return _anchorWnd;
  }

  int _findMainWindow(); // from _ProgramWindow

  @override
  void showLandmarks(List<({int x, int y})> points, int rgb, int size) {
    if (points.isEmpty || size <= 0) return hideLandmarks();
    final r = size / 2;
    final pad = (r + 3).ceil();
    var x0 = points.first.x, y0 = points.first.y, x1 = x0, y1 = y0;
    for (final p in points) {
      x0 = math.min(x0, p.x);
      y0 = math.min(y0, p.y);
      x1 = math.max(x1, p.x);
      y1 = math.max(y1, p.y);
    }
    final left = x0 - pad, top = y0 - pad;
    final w = x1 - x0 + 2 * pad + 1, h = y1 - y0 + 2 * pad + 1;
    if (_landmarksWnd == 0) {
      final cls = 'Static'.toNativeUtf16();
      final title = ''.toNativeUtf16();
      // LAYERED | TRANSPARENT (click-through) | TOPMOST | TOOLWINDOW | NOACTIVATE
      _landmarksWnd = _CreateWindowExW(0x00080000 | 0x20 | 0x8 | 0x80 | 0x08000000, cls, title,
          0x80000000, 0, 0, 1, 1, _anchor(), 0, 0, nullptr);
      calloc.free(cls);
      calloc.free(title);
      if (_landmarksWnd == 0) return;
    }
    final screen = _GetDC(0);
    final dc = _CreateCompatibleDC(screen);
    final bmi = calloc<Uint8>(64);
    final bitsPtr = calloc<Pointer<Uint8>>();
    final dst = calloc<Int32>(2), sz = calloc<Int32>(2), src = calloc<Int32>(2);
    final blend = calloc<Uint8>(4);
    var bmp = 0;
    try {
      final d = ByteData.sublistView(bmi.asTypedList(64));
      d.setUint32(0, 40, Endian.little);
      d.setInt32(4, w, Endian.little);
      d.setInt32(8, -h, Endian.little);
      d.setUint16(12, 1, Endian.little);
      d.setUint16(14, 32, Endian.little);
      bmp = _CreateDIBSection(screen, bmi, 0, bitsPtr, 0, 0); // zeroed = clear
      if (bmp == 0 || bitsPtr.value == nullptr) return;
      final px = bitsPtr.value.asTypedList(w * h * 4);
      for (final p in points) {
        drawLandmark(px, w, h, p.x - left, p.y - top, r, rgb);
      }
      _SelectObject(dc, bmp);
      dst[0] = left;
      dst[1] = top;
      sz[0] = w;
      sz[1] = h;
      blend[2] = 255; // SourceConstantAlpha
      blend[3] = 1; // AC_SRC_ALPHA
      _UpdateLayeredWindow(_landmarksWnd, 0, dst, sz, dc, src, 0, blend, 2);
      _ShowWindow(_landmarksWnd, 4); // SW_SHOWNOACTIVATE
    } finally {
      if (bmp != 0) _DeleteObject(bmp);
      _DeleteDC(dc);
      _ReleaseDC(0, screen);
      calloc.free(bmi);
      calloc.free(bitsPtr);
      calloc.free(dst);
      calloc.free(sz);
      calloc.free(src);
      calloc.free(blend);
    }
  }

  @override
  void hideLandmarks() {
    if (_landmarksWnd != 0) _DestroyWindow(_landmarksWnd);
    _landmarksWnd = 0;
  }
}

/// Draws one landmark into premultiplied BGRA [px] ([w]×[h]): a dot of
/// [rgb] with radius [r] and a white edge, centred at [cx], [cy]. Pure.
void drawLandmark(Uint8List px, int w, int h, int cx, int cy, double r, int rgb) {
  final reach = (r + 2).ceil();
  for (var y = cy - reach; y <= cy + reach; y++) {
    if (y < 0 || y >= h) continue;
    for (var x = cx - reach; x <= cx + reach; x++) {
      if (x < 0 || x >= w) continue;
      final d = math.sqrt(math.pow(x - cx, 2) + math.pow(y - cy, 2));
      final edge = r + 1.5; // white ring 1.5 px wide outside the dot
      if (d > edge + 0.5) continue;
      final a = (edge + 0.5 - d).clamp(0.0, 1.0);
      final c = d <= r ? rgb : 0xFFFFFF;
      final alpha = (255 * a).round();
      final i = (y * w + x) * 4;
      if (alpha <= px[i + 3]) continue; // an earlier dot is on top already
      px[i] = (c & 0xFF) * alpha ~/ 255;
      px[i + 1] = ((c >> 8) & 0xFF) * alpha ~/ 255;
      px[i + 2] = ((c >> 16) & 0xFF) * alpha ~/ 255;
      px[i + 3] = alpha;
    }
  }
}
