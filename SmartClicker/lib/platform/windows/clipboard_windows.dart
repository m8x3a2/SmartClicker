// Win32 names are kept as-is for readability.
// ignore_for_file: non_constant_identifier_names
// The clipboard beyond plain text: its change number, a list of files
// (CF_HDROP), a picture (CF_DIB) and the marks of password managers that ask
// not to keep what they copied. Used by the clipboard history.
part of 'windows_backend.dart';

final _GetClipboardSequenceNumber =
    _user32.lookupFunction<Uint32 Function(), int Function()>('GetClipboardSequenceNumber');
final _IsClipboardFormatAvailable =
    _user32.lookupFunction<Int32 Function(Uint32), int Function(int)>('IsClipboardFormatAvailable');
final _RegisterClipboardFormatW = _user32.lookupFunction<Uint32 Function(Pointer<Utf16>),
    int Function(Pointer<Utf16>)>('RegisterClipboardFormatW');
final _GlobalSize =
    _kernel32.lookupFunction<IntPtr Function(IntPtr), int Function(int)>('GlobalSize');
final _DragQueryFileW = DynamicLibrary.open('shell32.dll').lookupFunction<
    Uint32 Function(IntPtr, Uint32, Pointer<Uint16>, Uint32),
    int Function(int, int, Pointer<Uint16>, int)>('DragQueryFileW');

const _cfDib = 8, _cfHdrop = 15, _cfUnicodeText = 13;

int _registerFormat(String name) {
  final p = name.toNativeUtf16();
  try {
    return _RegisterClipboardFormatW(p);
  } finally {
    calloc.free(p);
  }
}

mixin _ClipboardWindows implements PlatformBackend {
  bool _openClipboard();

  late final int _cfExclude = _registerFormat('ExcludeClipboardContentFromMonitorProcessing');
  late final int _cfHistory = _registerFormat('CanIncludeInClipboardHistory');
  late final int _cfViewerIgnore = _registerFormat('Clipboard Viewer Ignore');

  @override
  int clipboardSequence() => _GetClipboardSequenceNumber();

  @override
  ClipData? readClipboard() {
    if (!_openClipboard()) return null;
    try {
      // Password managers mark what must not be remembered.
      var private = _IsClipboardFormatAvailable(_cfExclude) != 0 ||
          _IsClipboardFormatAvailable(_cfViewerIgnore) != 0;
      if (!private && _IsClipboardFormatAvailable(_cfHistory) != 0) {
        final h = _GetClipboardData(_cfHistory);
        final p = h == 0 ? nullptr : _GlobalLock(h).cast<Uint32>();
        if (p != nullptr) {
          private = p.value == 0;
          _GlobalUnlock(h);
        }
      }
      if (private) return const ClipData(private: true);
      if (_IsClipboardFormatAvailable(_cfHdrop) != 0) {
        final files = _readFiles();
        if (files.isNotEmpty) return ClipData(files: files);
      }
      if (_IsClipboardFormatAvailable(_cfDib) != 0) {
        final img = _readDib();
        if (img != null) return ClipData(image: img);
      }
      if (_IsClipboardFormatAvailable(_cfUnicodeText) != 0) {
        final h = _GetClipboardData(_cfUnicodeText);
        final p = h == 0 ? nullptr : _GlobalLock(h);
        if (p != nullptr) {
          try {
            return ClipData(text: p.cast<Utf16>().toDartString());
          } finally {
            _GlobalUnlock(h);
          }
        }
      }
      return const ClipData();
    } finally {
      _CloseClipboard();
    }
  }

  List<String> _readFiles() {
    final h = _GetClipboardData(_cfHdrop);
    if (h == 0) return const [];
    final n = _DragQueryFileW(h, 0xFFFFFFFF, nullptr, 0);
    final out = <String>[];
    final buf = calloc<Uint16>(4096);
    try {
      for (var i = 0; i < n; i++) {
        final len = _DragQueryFileW(h, i, buf, 4096);
        if (len > 0) out.add(buf.cast<Utf16>().toDartString(length: len));
      }
    } finally {
      calloc.free(buf);
    }
    return out;
  }

  /// CF_DIB (24 or 32 bits, uncompressed or with masks) → BGRA, top row first.
  ({int w, int h, Uint8List bgra})? _readDib() {
    final h = _GetClipboardData(_cfDib);
    if (h == 0) return null;
    final p = _GlobalLock(h).cast<Uint8>();
    if (p == nullptr) return null;
    try {
      final size = _GlobalSize(h);
      if (size < 40) return null;
      final b = p.asTypedList(size);
      final d = ByteData.sublistView(b);
      final hdr = d.getUint32(0, Endian.little);
      final w = d.getInt32(4, Endian.little);
      final rawH = d.getInt32(8, Endian.little);
      final bits = d.getUint16(14, Endian.little);
      final comp = d.getUint32(16, Endian.little);
      final hgt = rawH.abs();
      if (w <= 0 || hgt <= 0 || w * hgt > 40000000) return null;
      if ((bits != 32 && bits != 24) || (comp != 0 && comp != 3)) return null;
      final masks = comp == 3 && hdr == 40 ? 12 : 0;
      final colors = d.getUint32(32, Endian.little);
      final start = hdr + masks + colors * 4;
      final stride = ((w * bits + 31) ~/ 32) * 4;
      if (start + stride * hgt > size) return null;
      final out = Uint8List(w * hgt * 4);
      final bottomUp = rawH > 0;
      final bpp = bits ~/ 8;
      for (var y = 0; y < hgt; y++) {
        final src = start + (bottomUp ? hgt - 1 - y : y) * stride;
        for (var x = 0; x < w; x++) {
          final s = src + x * bpp, o = (y * w + x) * 4;
          out[o] = b[s];
          out[o + 1] = b[s + 1];
          out[o + 2] = b[s + 2];
          out[o + 3] = 255; // the alpha of a DIB is not reliable
        }
      }
      return (w: w, h: hgt, bgra: out);
    } finally {
      _GlobalUnlock(h);
    }
  }

  @override
  bool setClipboardFiles(List<String> paths) {
    if (paths.isEmpty) return false;
    // DROPFILES (20 bytes) + the paths, each ending with 0, and one more 0.
    final units = <int>[
      for (final f in paths) ...[...f.codeUnits, 0],
      0,
    ];
    final total = 20 + units.length * 2;
    if (!_openClipboard()) return false;
    try {
      _EmptyClipboard();
      final h = _GlobalAlloc(0x0042, total); // GMEM_MOVEABLE | GMEM_ZEROINIT
      if (h == 0) return false;
      final p = _GlobalLock(h).cast<Uint8>();
      final d = ByteData.sublistView(p.asTypedList(total));
      d.setUint32(0, 20, Endian.little); // pFiles: where the list starts
      d.setUint32(16, 1, Endian.little); // fWide: UTF-16
      for (var i = 0; i < units.length; i++) {
        d.setUint16(20 + i * 2, units[i], Endian.little);
      }
      _GlobalUnlock(h);
      return _SetClipboardData(_cfHdrop, h) != 0;
    } finally {
      _CloseClipboard();
    }
  }

  @override
  bool setClipboardImage(int w, int h, Uint8List bgra) {
    final stride = w * 4;
    final total = 40 + stride * h;
    if (!_openClipboard()) return false;
    try {
      _EmptyClipboard();
      final g = _GlobalAlloc(0x0042, total);
      if (g == 0) return false;
      final p = _GlobalLock(g).cast<Uint8>();
      final b = p.asTypedList(total);
      final d = ByteData.sublistView(b);
      d.setUint32(0, 40, Endian.little); // BITMAPINFOHEADER
      d.setInt32(4, w, Endian.little);
      d.setInt32(8, h, Endian.little); // bottom row first
      d.setUint16(12, 1, Endian.little);
      d.setUint16(14, 32, Endian.little);
      d.setUint32(20, stride * h, Endian.little);
      for (var y = 0; y < h; y++) {
        final dst = 40 + (h - 1 - y) * stride;
        b.setRange(dst, dst + stride, bgra, y * stride);
      }
      _GlobalUnlock(g);
      return _SetClipboardData(_cfDib, g) != 0;
    } finally {
      _CloseClipboard();
    }
  }
}
