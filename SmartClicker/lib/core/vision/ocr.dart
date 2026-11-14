// Text recognition entry point shared by scripts and the interface.

import '../../platform/backend.dart';
import 'image.dart';
import 'paddle_ocr.dart';

const ocrEngineLabels = {
  'paddle': 'Точное (PaddleOCR)',
  'windows': 'Быстрое (встроенное в Windows)',
};

/// Engine id for what the user wrote in `engine: "..."`.
String ocrEngineId(String name) => switch (name.trim().toLowerCase()) {
      '' || 'windows' || 'fast' || 'быстро' || 'быстрое' => 'windows',
      'paddle' || 'paddleocr' || 'accurate' || 'точно' || 'точное' => 'paddle',
      _ => throw ArgumentError(
          'неизвестный движок "$name" — есть "windows" (быстрое) и "paddle" (точное)'),
    };

String ocrBitmap(PlatformBackend backend, Bitmap img,
    {String engine = 'windows', String lang = '', int scale = 0, String ocrDir = ''}) {
  if (engine == 'paddle') return PaddleOcr.open(ocrDir).read(img);
  return backend.ocrImage(img.bgra, img.w, img.h, lang: lang, scale: scale);
}

const _lookalikes = {
  'a': 'а', 'b': 'в', 'c': 'с', 'e': 'е', 'h': 'н', 'k': 'к', 'm': 'м',
  'o': 'о', 'p': 'р', 't': 'т', 'x': 'х', 'y': 'у', 'ё': 'е',
};

/// Form of a text for comparing with recognized text: lower case, single
/// spaces, and Latin letters that look like Cyrillic ones are made the same
/// (recognition mixes them up: "Paddle" may come back as "Раddlе").
String looseText(String s) {
  final out = StringBuffer();
  for (final ch in s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim().split('')) {
    out.write(_lookalikes[ch] ?? ch);
  }
  return out.toString();
}
