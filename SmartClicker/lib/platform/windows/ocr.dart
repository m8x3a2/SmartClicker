// Text recognition with the OCR engine built into Windows 10/11
// (Windows.Media.Ocr), called through raw WinRT vtables: no plugins, no
// network, nothing to download.
// ignore_for_file: non_constant_identifier_names

import 'dart:ffi';
import 'dart:io' show sleep;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'com.dart';

final _combase = DynamicLibrary.open('combase.dll');

final _CoIncrementMTAUsage = _combase.lookupFunction<
    Int32 Function(Pointer<IntPtr>),
    int Function(Pointer<IntPtr>)>('CoIncrementMTAUsage');
final _RoGetActivationFactory = _combase.lookupFunction<
    Int32 Function(IntPtr, Pointer<Uint8>, Pointer<Pointer<Void>>),
    int Function(
        int, Pointer<Uint8>, Pointer<Pointer<Void>>)>('RoGetActivationFactory');
final _WindowsCreateString = _combase.lookupFunction<
    Int32 Function(Pointer<Utf16>, Uint32, Pointer<IntPtr>),
    int Function(Pointer<Utf16>, int, Pointer<IntPtr>)>('WindowsCreateString');
final _WindowsDeleteString = _combase
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('WindowsDeleteString');
final _WindowsGetStringRawBuffer = _combase.lookupFunction<
    Pointer<Uint16> Function(IntPtr, Pointer<Uint32>),
    Pointer<Uint16> Function(
        int, Pointer<Uint32>)>('WindowsGetStringRawBuffer');

typedef _P = Pointer<Void>;
typedef _Out = Pointer<Pointer<Void>>;

class OcrException implements Exception {
  final String message;
  OcrException(this.message);
  @override
  String toString() => message;
}

// ---- vtable calls ---------------------------------------------------------

/// (this, out*) -> HRESULT
int _get(_P obj, int index, Pointer out) =>
    comSlot<Int32 Function(_P, Pointer)>(obj, index)
        .asFunction<int Function(_P, Pointer)>()(obj, out);

/// (this, pointer-sized in, out*) -> HRESULT
int _inOut(_P obj, int index, int arg, Pointer out) =>
    comSlot<Int32 Function(_P, IntPtr, Pointer)>(obj, index)
        .asFunction<int Function(_P, int, Pointer)>()(obj, arg, out);

/// (this, uint32 in, out*) -> HRESULT
int _u32Out(_P obj, int index, int arg, Pointer out) =>
    comSlot<Int32 Function(_P, Uint32, Pointer)>(obj, index)
        .asFunction<int Function(_P, int, Pointer)>()(obj, arg, out);

_P _query(_P obj, String iid) {
  final g = guidBytes(iid);
  final out = calloc<Pointer<Void>>();
  try {
    final hr = comSlot<Int32 Function(_P, Pointer<Uint8>, _Out)>(obj, 0)
        .asFunction<int Function(_P, Pointer<Uint8>, _Out)>()(obj, g, out);
    if (hr < 0) throw OcrException('OCR: внутренняя ошибка (QI $iid)');
    return out.value;
  } finally {
    calloc.free(g);
    calloc.free(out);
  }
}

int _hstring(String s) {
  final p = s.toNativeUtf16();
  final out = calloc<IntPtr>();
  try {
    _WindowsCreateString(p, s.length, out);
    return out.value;
  } finally {
    calloc.free(p);
    calloc.free(out);
  }
}

String _fromHstring(int h) {
  if (h == 0) return '';
  final len = calloc<Uint32>();
  try {
    final p = _WindowsGetStringRawBuffer(h, len);
    return String.fromCharCodes(p.asTypedList(len.value));
  } finally {
    calloc.free(len);
  }
}

_P _factory(String cls, String iid) {
  final name = _hstring(cls);
  final g = guidBytes(iid);
  final out = calloc<Pointer<Void>>();
  try {
    final hr = _RoGetActivationFactory(name, g, out);
    if (hr < 0) {
      throw OcrException(
          'распознавание текста недоступно в этой версии Windows ($cls)');
    }
    return out.value;
  } finally {
    _WindowsDeleteString(name);
    calloc.free(g);
    calloc.free(out);
  }
}

// ---- engine ---------------------------------------------------------------

bool _mta = false;
final Map<String, _P> _engines = {}; // language tag ('' = user languages)

void _ensureMta() {
  if (_mta) return;
  final cookie = calloc<IntPtr>();
  _CoIncrementMTAUsage(cookie); // keeps the MTA alive for every thread
  calloc.free(cookie);
  _mta = true;
}

_P _engine(String lang) {
  final cached = _engines[lang];
  if (cached != null) return cached;
  _ensureMta();
  final statics = _factory('Windows.Media.Ocr.OcrEngine',
      '5bffa85a-3384-3540-9940-699120d428a8');
  final out = calloc<Pointer<Void>>();
  try {
    if (lang.isEmpty) {
      _get(statics, 10, out); // TryCreateFromUserProfileLanguages
    } else {
      final lf = _factory('Windows.Globalization.Language',
          '9b0252ac-0c27-44f8-b792-9793fb66c63e');
      final tag = _hstring(lang);
      final language = calloc<Pointer<Void>>();
      try {
        if (_inOut(lf, 6, tag, language) >= 0 && language.value != nullptr) {
          _inOut(statics, 9, language.value.address, out); // TryCreateFromLanguage
          comRelease(language.value);
        }
      } finally {
        _WindowsDeleteString(tag);
        calloc.free(language);
        comRelease(lf);
      }
    }
    if (out.value == nullptr) {
      throw OcrException(lang.isEmpty
          ? 'в Windows не установлен ни один язык распознавания текста '
              '(Параметры → Время и язык → Язык → добавить язык с «Оптическим распознаванием»)'
          : 'язык распознавания "$lang" не установлен в Windows '
              '(Параметры → Время и язык → Язык; примеры: "ru", "en-US")');
    }
    return _engines[lang] = out.value;
  } finally {
    calloc.free(out);
    comRelease(statics);
  }
}

/// Recognizes text in a top-down BGRA image. Lines are separated by "\n".
/// [lang]: BCP-47 tag ("ru", "en-US"); empty = the user's Windows languages.
String ocrBgra(Uint8List bgra, int w, int h, {String lang = ''}) {
  if (w <= 0 || h <= 0) return '';
  final engine = _engine(lang);
  final out = calloc<Pointer<Void>>();
  _P buffer = nullptr, access = nullptr, bitmap = nullptr;
  _P op = nullptr, info = nullptr, result = nullptr, lines = nullptr;
  final bf = _factory('Windows.Storage.Streams.Buffer',
      '71af914d-c10f-484b-bc50-14bc623b3a27');
  final sb = _factory('Windows.Graphics.Imaging.SoftwareBitmap',
      'df0385db-672f-4a9d-806e-c2442f343e86');
  try {
    final bytes = w * h * 4;
    if (_u32Out(bf, 6, bytes, out) < 0) throw OcrException('OCR: нет памяти');
    buffer = out.value;
    // IBuffer.put_Length
    comSlot<Int32 Function(_P, Uint32)>(buffer, 8)
        .asFunction<int Function(_P, int)>()(buffer, bytes);
    access = _query(buffer, '905a0fef-bc53-11df-8c49-001e4fc686da');
    final data = calloc<Pointer<Uint8>>();
    _get(access, 3, data);
    data.value.asTypedList(bytes).setAll(0, bgra);
    calloc.free(data);

    // CreateCopyWithAlphaFromBuffer(buffer, Bgra8 = 87, w, h, Ignore = 2)
    out.value = nullptr;
    final hr = comSlot<Int32 Function(_P, _P, Int32, Int32, Int32, Int32, _Out)>(
            sb, 10)
        .asFunction<int Function(_P, _P, int, int, int, int, _Out)>()(
        sb, buffer, 87, w, h, 2, out);
    if (hr < 0 || out.value == nullptr) {
      throw OcrException('OCR: не удалось подготовить картинку ${w}x$h');
    }
    bitmap = out.value;

    out.value = nullptr;
    if (_inOut(engine, 6, bitmap.address, out) < 0 || out.value == nullptr) {
      throw OcrException('OCR: картинка ${w}x$h не подходит (слишком большая?)');
    }
    op = out.value;
    info = _query(op, '00000036-0000-0000-c000-000000000046'); // IAsyncInfo
    final status = calloc<Int32>();
    try {
      for (var i = 0; i < 4000; i++) {
        _get(info, 7, status);
        if (status.value != 0) break;
        sleep(const Duration(milliseconds: 5));
      }
      if (status.value != 1) throw OcrException('OCR: распознавание не удалось');
    } finally {
      calloc.free(status);
    }
    out.value = nullptr;
    if (_get(op, 8, out) < 0 || out.value == nullptr) {
      throw OcrException('OCR: нет результата');
    }
    result = out.value;

    out.value = nullptr;
    _get(result, 6, out); // get_Lines
    lines = out.value;
    if (lines == nullptr) return '';
    final n = calloc<Uint32>();
    final hs = calloc<IntPtr>();
    final sbuf = StringBuffer();
    try {
      _get(lines, 7, n);
      for (var i = 0; i < n.value; i++) {
        out.value = nullptr;
        if (_u32Out(lines, 6, i, out) < 0 || out.value == nullptr) continue;
        hs.value = 0;
        _get(out.value, 7, hs); // IOcrLine.get_Text
        if (i > 0) sbuf.write('\n');
        sbuf.write(_fromHstring(hs.value));
        _WindowsDeleteString(hs.value);
        comRelease(out.value);
      }
    } finally {
      calloc.free(n);
      calloc.free(hs);
    }
    return sbuf.toString();
  } finally {
    for (final p in [lines, result, info, op, bitmap, access, buffer, sb, bf]) {
      comRelease(p);
    }
    calloc.free(out);
  }
}

/// Language tags the installed Windows can recognize.
List<String> ocrLanguages() {
  _ensureMta();
  final statics = _factory('Windows.Media.Ocr.OcrEngine',
      '5bffa85a-3384-3540-9940-699120d428a8');
  final out = calloc<Pointer<Void>>();
  final n = calloc<Uint32>();
  final hs = calloc<IntPtr>();
  final res = <String>[];
  try {
    if (_get(statics, 7, out) < 0 || out.value == nullptr) return res;
    final list = out.value;
    _get(list, 7, n);
    for (var i = 0; i < n.value; i++) {
      out.value = nullptr;
      if (_u32Out(list, 6, i, out) < 0 || out.value == nullptr) continue;
      hs.value = 0;
      _get(out.value, 6, hs); // ILanguage.get_LanguageTag
      res.add(_fromHstring(hs.value));
      _WindowsDeleteString(hs.value);
      comRelease(out.value);
    }
    comRelease(list);
    return res;
  } finally {
    calloc.free(out);
    calloc.free(n);
    calloc.free(hs);
    comRelease(statics);
  }
}
