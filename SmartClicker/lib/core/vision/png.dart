// PNG files: own encoder and decoder (no packages).

import 'dart:io';
import 'dart:typed_data';
import '../storage/zip.dart' show crc32;
import 'bitmap.dart';

const _pngMagic = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

Uint8List pngEncode(Bitmap b) {
  final stride = b.w * 3 + 1;
  final raw = Uint8List(stride * b.h);
  for (var y = 0; y < b.h; y++) {
    var o = y * stride + 1; // filter byte 0
    var i = y * b.w * 4;
    for (var x = 0; x < b.w; x++, i += 4) {
      raw[o++] = b.bgra[i + 2];
      raw[o++] = b.bgra[i + 1];
      raw[o++] = b.bgra[i];
    }
  }
  final out = BytesBuilder();
  void chunk(String type, List<int> data) {
    final body = [...type.codeUnits, ...data];
    final len = ByteData(4)..setUint32(0, data.length);
    final crc = ByteData(4)..setUint32(0, crc32(body));
    out
      ..add(len.buffer.asUint8List())
      ..add(body)
      ..add(crc.buffer.asUint8List());
  }

  final ihdr = ByteData(13)
    ..setUint32(0, b.w)
    ..setUint32(4, b.h)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 2); // RGB
  out.add(_pngMagic);
  chunk('IHDR', ihdr.buffer.asUint8List());
  chunk('IDAT', zlib.encode(raw));
  chunk('IEND', const []);
  return out.toBytes();
}

/// Decodes a PNG (8/16-bit, any colour type, not interlaced).
Bitmap pngDecode(Uint8List bytes) {
  if (bytes.length < 33) throw const FormatException('это не PNG-картинка');
  for (var i = 0; i < 8; i++) {
    if (bytes[i] != _pngMagic[i]) {
      throw const FormatException('это не PNG-картинка');
    }
  }
  final d = ByteData.sublistView(bytes);
  var pos = 8;
  var w = 0, h = 0, depth = 8, type = 2;
  Uint8List? palette, trns;
  final idat = BytesBuilder(copy: false);
  while (pos + 8 <= bytes.length) {
    final len = d.getUint32(pos);
    final name = String.fromCharCodes(bytes, pos + 4, pos + 8);
    final start = pos + 8;
    if (start + len > bytes.length) break;
    final data = Uint8List.sublistView(bytes, start, start + len);
    switch (name) {
      case 'IHDR':
        w = d.getUint32(start);
        h = d.getUint32(start + 4);
        depth = data[8];
        type = data[9];
        if (data[12] != 0) {
          throw const FormatException(
              'PNG с чересстрочной развёрткой не поддерживается — пересохраните картинку');
        }
      case 'PLTE':
        palette = data;
      case 'tRNS':
        trns = data;
      case 'IDAT':
        idat.add(data);
    }
    if (name == 'IEND') break;
    pos = start + len + 4;
  }
  if (w <= 0 || h <= 0 || (depth != 8 && depth != 16)) {
    throw const FormatException(
        'этот PNG не поддерживается (нужна обычная 8-битная картинка)');
  }
  final channels = const {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[type];
  if (channels == null) throw const FormatException('повреждённый PNG');
  final bpp = channels * (depth ~/ 8);
  final stride = w * bpp;
  final raw = Uint8List.fromList(zlib.decode(idat.takeBytes()));
  if (raw.length < (stride + 1) * h) throw const FormatException('повреждённый PNG');
  // Undo the row filters in place.
  for (var y = 0; y < h; y++) {
    final row = y * (stride + 1) + 1;
    final prev = row - stride - 1;
    final filter = raw[row - 1];
    for (var i = 0; i < stride; i++) {
      final a = i >= bpp ? raw[row + i - bpp] : 0;
      final b = y > 0 ? raw[prev + i] : 0;
      final c = (y > 0 && i >= bpp) ? raw[prev + i - bpp] : 0;
      int add;
      switch (filter) {
        case 1:
          add = a;
        case 2:
          add = b;
        case 3:
          add = (a + b) >> 1;
        case 4:
          final p = a + b - c;
          final pa = (p - a).abs(), pb = (p - b).abs(), pc = (p - c).abs();
          add = (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c);
        default:
          add = 0;
      }
      raw[row + i] = (raw[row + i] + add) & 0xFF;
    }
  }
  final out = Uint8List(w * h * 4);
  final step = depth ~/ 8; // take the high byte of 16-bit samples
  var o = 0;
  for (var y = 0; y < h; y++) {
    var i = y * (stride + 1) + 1;
    for (var x = 0; x < w; x++, i += bpp, o += 4) {
      int r, g, b, a = 255;
      switch (type) {
        case 0:
          r = g = b = raw[i];
        case 2:
          r = raw[i];
          g = raw[i + step];
          b = raw[i + 2 * step];
        case 3:
          final p = raw[i] * 3;
          if (palette == null || p + 2 >= palette.length) {
            r = g = b = 0;
          } else {
            r = palette[p];
            g = palette[p + 1];
            b = palette[p + 2];
          }
          if (trns != null && raw[i] < trns.length) a = trns[raw[i]];
        case 4:
          r = g = b = raw[i];
          a = raw[i + step];
        default:
          r = raw[i];
          g = raw[i + step];
          b = raw[i + 2 * step];
          a = raw[i + 3 * step];
      }
      out[o] = b;
      out[o + 1] = g;
      out[o + 2] = r;
      out[o + 3] = a;
    }
  }
  return Bitmap(w, h, out);
}
