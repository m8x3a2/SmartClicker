// Own ZIP reader and writer (no packages) and CRC-32.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Minimal ZIP writer/reader (deflate or stored, UTF-8 names): enough to
/// export and import scripts without an extra dependency.

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

class _W {
  final BytesBuilder b = BytesBuilder();
  void u16(int v) => b.add([v & 0xFF, (v >> 8) & 0xFF]);
  void u32(int v) =>
      b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
}

Uint8List zipEncode(Map<String, List<int>> files) {
  final out = _W();
  final central = _W();
  var count = 0;
  files.forEach((name, data) {
    final nameBytes = utf8.encode(name);
    final packed = ZLibEncoder(raw: true).convert(data);
    final crc = crc32(data);
    final offset = out.b.length;
    void header(_W w) {
      w.u16(20); // version needed
      w.u16(0x0800); // UTF-8 names
      w.u16(8); // deflate
      w.u16(0); // time
      w.u16(0x21); // date: 1980-01-01
      w.u32(crc);
      w.u32(packed.length);
      w.u32(data.length);
      w.u16(nameBytes.length);
      w.u16(0); // extra
    }

    out.u32(0x04034b50);
    header(out);
    out.b.add(nameBytes);
    out.b.add(packed);

    central.u32(0x02014b50);
    central.u16(20); // version made by
    header(central);
    central.u16(0); // comment
    central.u16(0); // disk
    central.u16(0); // internal attributes
    central.u32(0); // external attributes
    central.u32(offset);
    central.b.add(nameBytes);
    count++;
  });
  final cdOffset = out.b.length;
  final cd = central.b.toBytes();
  out.b.add(cd);
  out.u32(0x06054b50);
  out.u16(0);
  out.u16(0);
  out.u16(count);
  out.u16(count);
  out.u32(cd.length);
  out.u32(cdOffset);
  out.u16(0);
  return out.b.toBytes();
}

/// Returns file name -> content. Throws [FormatException] on a bad archive.
/// With [only], just the matching files are unpacked.
Map<String, Uint8List> zipDecode(Uint8List bytes,
    {bool Function(String name)? only}) {
  final d = ByteData.sublistView(bytes);
  var eocd = -1;
  for (var i = bytes.length - 22; i >= 0 && i >= bytes.length - 70000; i--) {
    if (d.getUint32(i, Endian.little) == 0x06054b50) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw const FormatException('это не ZIP-архив');
  final count = d.getUint16(eocd + 10, Endian.little);
  var p = d.getUint32(eocd + 16, Endian.little);
  final out = <String, Uint8List>{};
  for (var n = 0; n < count; n++) {
    if (p + 46 > bytes.length || d.getUint32(p, Endian.little) != 0x02014b50) {
      throw const FormatException('архив повреждён');
    }
    final method = d.getUint16(p + 10, Endian.little);
    final csize = d.getUint32(p + 20, Endian.little);
    final nameLen = d.getUint16(p + 28, Endian.little);
    final extraLen = d.getUint16(p + 30, Endian.little);
    final commentLen = d.getUint16(p + 32, Endian.little);
    final local = d.getUint32(p + 42, Endian.little);
    final name = utf8.decode(bytes.sublist(p + 46, p + 46 + nameLen),
        allowMalformed: true);
    p += 46 + nameLen + extraLen + commentLen;
    if (name.endsWith('/')) continue;
    if (only != null && !only(name)) continue;
    final ln = d.getUint16(local + 26, Endian.little);
    final le = d.getUint16(local + 28, Endian.little);
    final start = local + 30 + ln + le;
    final raw = bytes.sublist(start, start + csize);
    if (method == 0) {
      out[name] = raw;
    } else if (method == 8) {
      out[name] = Uint8List.fromList(ZLibDecoder(raw: true).convert(raw));
    } else {
      throw FormatException('неподдерживаемое сжатие в файле $name');
    }
  }
  return out;
}
