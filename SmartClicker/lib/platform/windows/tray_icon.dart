// Win32 names are kept as-is for readability.
// ignore_for_file: non_constant_identifier_names
// The tray icon with a coloured status dot in its corner (running, paused,
// stopped with an error), drawn into a copy of the program's own icon.

import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

final _user32 = DynamicLibrary.open('user32.dll');
final _gdi32 = DynamicLibrary.open('gdi32.dll');

final _GetIconInfo = _user32.lookupFunction<Int32 Function(IntPtr, Pointer<Uint8>),
    int Function(int, Pointer<Uint8>)>('GetIconInfo');
final _CreateIconIndirect = _user32.lookupFunction<IntPtr Function(Pointer<Uint8>),
    int Function(Pointer<Uint8>)>('CreateIconIndirect');
final _GetDC = _user32.lookupFunction<IntPtr Function(IntPtr), int Function(int)>('GetDC');
final _ReleaseDC =
    _user32.lookupFunction<Int32 Function(IntPtr, IntPtr), int Function(int, int)>('ReleaseDC');
final _GetDIBits = _gdi32.lookupFunction<
    Int32 Function(IntPtr, IntPtr, Uint32, Uint32, Pointer<Uint8>, Pointer<Uint8>, Uint32),
    int Function(int, int, int, int, Pointer<Uint8>, Pointer<Uint8>, int)>('GetDIBits');
final _CreateDIBSection = _gdi32.lookupFunction<
    IntPtr Function(IntPtr, Pointer<Uint8>, Uint32, Pointer<Pointer<Uint8>>, IntPtr, Uint32),
    int Function(int, Pointer<Uint8>, int, Pointer<Pointer<Uint8>>, int, int)>('CreateDIBSection');
final _CreateBitmap = _gdi32.lookupFunction<
    IntPtr Function(Int32, Int32, Uint32, Uint32, Pointer<Void>),
    int Function(int, int, int, int, Pointer<Void>)>('CreateBitmap');
final _DeleteObject =
    _gdi32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('DeleteObject');

/// Colours of the status dots (0xRRGGBB).
const trayMarkColors = {'run': 0x2FB344, 'pause': 0xF2B600, 'error': 0xE03131};

/// Draws a dot of [rgb] into BGRA [px] ([size]×[size], top-down): a filled
/// circle in the bottom right corner with a thin dark ring, so it shows
/// both on a light and on a dark taskbar. Pure — tested without Windows.
void drawStatusDot(Uint8List px, int size, int rgb) {
  final r = size * 0.27;
  final cx = size - r - 0.5, cy = size - r - 0.5;
  final ring = math.max(1.0, size / 16);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final d = math.sqrt(math.pow(x + 0.5 - cx, 2) + math.pow(y + 0.5 - cy, 2));
      if (d > r + 0.5) continue;
      final i = (y * size + x) * 4;
      final inner = d <= r - ring;
      final c = inner ? rgb : 0x202020;
      // Soft edge: the outermost pixel is blended with what is under it.
      final a = (r + 0.5 - d).clamp(0.0, 1.0);
      px[i] = (px[i] * (1 - a) + (c & 0xFF) * a).round();
      px[i + 1] = (px[i + 1] * (1 - a) + ((c >> 8) & 0xFF) * a).round();
      px[i + 2] = (px[i + 2] * (1 - a) + ((c >> 16) & 0xFF) * a).round();
      px[i + 3] = math.max(px[i + 3], (255 * a).round());
    }
  }
}

/// A copy of icon [base] ([size]×[size] px) with a status dot of [rgb];
/// 0 if it cannot be made (the plain icon is used then).
int markedIcon(int base, int size, int rgb) {
  final info = calloc<Uint8>(32); // ICONINFO on x64
  final bmi = calloc<Uint8>(44); // BITMAPINFOHEADER + one colour
  final bits = calloc<Pointer<Uint8>>();
  final px = calloc<Uint8>(size * size * 4);
  final screen = _GetDC(0);
  var color = 0, mask = 0, made = 0;
  try {
    if (_GetIconInfo(base, info) == 0) return 0;
    final d = ByteData.sublistView(info.asTypedList(32));
    final oldMask = d.getUint64(16, Endian.little), oldColor = d.getUint64(24, Endian.little);
    final h = ByteData.sublistView(bmi.asTypedList(44));
    h.setUint32(0, 40, Endian.little);
    h.setInt32(4, size, Endian.little);
    h.setInt32(8, -size, Endian.little); // top-down
    h.setUint16(12, 1, Endian.little);
    h.setUint16(14, 32, Endian.little);
    final read = oldColor == 0 ? 0 : _GetDIBits(screen, oldColor, 0, size, px, bmi, 0);
    if (oldColor != 0) _DeleteObject(oldColor);
    if (oldMask != 0) _DeleteObject(oldMask);
    if (read == 0) return 0;
    final pixels = px.asTypedList(size * size * 4);
    // An icon without an alpha channel: every pixel counts as opaque.
    var anyAlpha = false;
    for (var i = 3; i < pixels.length; i += 4) {
      if (pixels[i] != 0) {
        anyAlpha = true;
        break;
      }
    }
    if (!anyAlpha) {
      for (var i = 3; i < pixels.length; i += 4) {
        pixels[i] = 255;
      }
    }
    drawStatusDot(pixels, size, rgb);
    color = _CreateDIBSection(screen, bmi, 0, bits, 0, 0);
    if (color == 0) return 0;
    bits.value.asTypedList(pixels.length).setAll(0, pixels);
    mask = _CreateBitmap(size, size, 1, 1, nullptr); // ignored with alpha
    final ni = ByteData.sublistView(info.asTypedList(32));
    ni.setUint32(0, 1, Endian.little); // fIcon
    ni.setUint64(16, mask, Endian.little);
    ni.setUint64(24, color, Endian.little);
    made = _CreateIconIndirect(info);
    return made;
  } finally {
    if (color != 0) _DeleteObject(color);
    if (mask != 0) _DeleteObject(mask);
    _ReleaseDC(0, screen);
    calloc.free(info);
    calloc.free(bmi);
    calloc.free(bits);
    calloc.free(px);
  }
}
