// Makes the tray icons with status dots on the real Windows and saves them
// enlarged as PNG for a look.   dart run tool/smoke_tray_icon.dart <folder>
// ignore_for_file: avoid_print, non_constant_identifier_names
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:smart_clicker/core/vision/bitmap.dart';
import 'package:smart_clicker/core/vision/png.dart';
import 'package:smart_clicker/platform/windows/tray_icon.dart';

final _user32 = DynamicLibrary.open('user32.dll');
final _gdi32 = DynamicLibrary.open('gdi32.dll');
final _LoadImageW = _user32.lookupFunction<
    IntPtr Function(IntPtr, IntPtr, Uint32, Int32, Int32, Uint32),
    int Function(int, int, int, int, int, int)>('LoadImageW');
final _GetIconInfo = _user32.lookupFunction<Int32 Function(IntPtr, Pointer<Uint8>),
    int Function(int, Pointer<Uint8>)>('GetIconInfo');
final _GetDC = _user32.lookupFunction<IntPtr Function(IntPtr), int Function(int)>('GetDC');
final _GetDIBits = _gdi32.lookupFunction<
    Int32 Function(IntPtr, IntPtr, Uint32, Uint32, Pointer<Uint8>, Pointer<Uint8>, Uint32),
    int Function(int, int, int, int, Pointer<Uint8>, Pointer<Uint8>, int)>('GetDIBits');

/// BGRA pixels of [icon], [size]×[size].
Uint8List pixelsOf(int icon, int size) {
  final info = calloc<Uint8>(32), bmi = calloc<Uint8>(44), px = calloc<Uint8>(size * size * 4);
  _GetIconInfo(icon, info);
  final color = ByteData.sublistView(info.asTypedList(32)).getUint64(24, Endian.little);
  final h = ByteData.sublistView(bmi.asTypedList(44));
  h.setUint32(0, 40, Endian.little);
  h.setInt32(4, size, Endian.little);
  h.setInt32(8, -size, Endian.little);
  h.setUint16(12, 1, Endian.little);
  h.setUint16(14, 32, Endian.little);
  _GetDIBits(_GetDC(0), color, 0, size, px, bmi, 0);
  return Uint8List.fromList(px.asTypedList(size * size * 4));
}

void main(List<String> args) {
  final dir = args.isEmpty ? Directory.systemTemp.path : args[0];
  const size = 32;
  // The standard application icon (the program's own lives in its exe).
  final base = _LoadImageW(0, 32512, 1, size, size, 0x8000);
  print('base icon: $base');
  var ok = base != 0;
  const scale = 6;
  final sheet = Uint8List(size * scale * 3 * size * scale * 4);
  var col = 0;
  for (final e in trayMarkColors.entries) {
    final icon = markedIcon(base, size, e.value);
    print('${e.key}: ${icon != 0 ? 'OK' : 'FAIL'}');
    ok &= icon != 0;
    if (icon == 0) continue;
    final px = pixelsOf(icon, size);
    for (var y = 0; y < size * scale; y++) {
      for (var x = 0; x < size * scale; x++) {
        final s = ((y ~/ scale) * size + x ~/ scale) * 4;
        final d = (y * size * scale * 3 + col * size * scale + x) * 4;
        // On a grey background, like a taskbar.
        final a = px[s + 3] / 255;
        for (var c = 0; c < 3; c++) {
          sheet[d + c] = (px[s + c] * a + 0x60 * (1 - a)).round();
        }
        sheet[d + 3] = 255;
      }
    }
    col++;
  }
  final out = '$dir${Platform.pathSeparator}tray_icons.png';
  File(out).writeAsBytesSync(pngEncode(Bitmap(size * scale * 3, size * scale, sheet)));
  print('saved $out');
  print(ok ? 'ALL OK' : 'FAIL');
  exit(ok ? 0 : 1);
}
