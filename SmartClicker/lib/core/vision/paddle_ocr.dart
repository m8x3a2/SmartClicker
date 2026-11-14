// PaddleOCR (PP-OCRv5 mobile, ONNX): the "accurate" text recognition.
// A detector finds the text lines of the region, a recognizer reads each of
// them. Slower than the OCR of the operating system, but reads small,
// coloured and stylised text much better. Works offline once the files are
// in place (see `app/ocr_install.dart`).
//
// The pipeline follows PaddleOCR's own pre/post-processing; the choice of
// models and the tuned constants come from the author's Comic Translate
// Screen project (Apache-2.0).

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../platform/onnx/ort.dart';
import 'image.dart';

const paddleDetModel = 'ch_PP-OCRv5_mobile_det.onnx';
const paddleRecModel = 'eslav_PP-OCRv5_rec_mobile_infer.onnx';
const paddleDict = 'ppocrv5_eslav_dict.txt';
final paddleRuntime = Platform.isWindows ? 'onnxruntime.dll' : 'libonnxruntime.so';

const _recHeight = 48;
const _recMinWidth = 320;

class OcrLine {
  final String text;
  final double confidence;
  final int x, y, w, h;
  const OcrLine(this.text, this.confidence, this.x, this.y, this.w, this.h);
}

class PaddleOcr {
  final OrtSession _det, _rec;
  final List<String> _dict;
  PaddleOcr._(this._det, this._rec, this._dict);

  static final Map<String, PaddleOcr> _cache = {};

  static String _p(String dir, String name) => '$dir${Platform.pathSeparator}$name';

  /// Files that are still missing in [dir].
  static List<String> missing(String dir) => [
        for (final f in [paddleRuntime, paddleDetModel, paddleRecModel, paddleDict])
          if (!File(_p(dir, f)).existsSync()) f,
      ];

  static bool installed(String dir) => missing(dir).isEmpty;

  /// Loads the models once per isolate.
  factory PaddleOcr.open(String dir) {
    final cached = _cache[dir];
    if (cached != null) return cached;
    final lost = missing(dir);
    if (lost.isNotEmpty) {
      throw OrtException('точное распознавание (PaddleOCR) не установлено — '
          'откройте «Инструменты» → «Картинки и текст» и нажмите «Установить PaddleOCR»');
    }
    final ort = Ort.open(_p(dir, paddleRuntime));
    final threads = math.max(1, math.min(4, Platform.numberOfProcessors));
    return _cache[dir] = PaddleOcr._(
      ort.session(_p(dir, paddleDetModel), threads: threads),
      ort.session(_p(dir, paddleRecModel), threads: threads),
      const LineSplitter().convert(File(_p(dir, paddleDict)).readAsStringSync()),
    );
  }

  /// Text of the picture, lines separated by a line break.
  String read(Bitmap img) => lines(img).map((l) => l.text).join('\n');

  /// Recognized lines, top to bottom; several pieces of one row are joined.
  List<OcrLine> lines(Bitmap img) {
    if (img.w < 4 || img.h < 4) return const [];
    var boxes = _detect(img);
    if (boxes.isEmpty && img.w >= img.h) {
      boxes = [(x: 0, y: 0, w: img.w, h: img.h)]; // maybe one tight line
    }
    // Group the boxes into rows.
    final rows = <List<({int x, int y, int w, int h})>>[];
    boxes.sort((a, b) => (a.y * 2 + a.h).compareTo(b.y * 2 + b.h));
    for (final b in boxes) {
      final cy = b.y + b.h / 2;
      List<({int x, int y, int w, int h})>? home;
      for (final row in rows) {
        final r = row.last;
        if ((cy - (r.y + r.h / 2)).abs() < math.min(b.h, r.h) * 0.5) {
          home = row;
          break;
        }
      }
      (home ?? (rows..add([])).last).add(b);
    }
    final out = <OcrLine>[];
    for (final row in rows) {
      row.sort((a, b) => a.x.compareTo(b.x));
      final parts = <String>[];
      var conf = 1.0;
      for (final b in row) {
        final r = _recognize(img, b.x, b.y, b.w, b.h);
        if (r.text.trim().isEmpty || r.confidence < 0.5) continue;
        parts.add(r.text.trim());
        conf = math.min(conf, r.confidence);
      }
      if (parts.isEmpty) continue;
      final x0 = row.map((b) => b.x).reduce(math.min);
      final y0 = row.map((b) => b.y).reduce(math.min);
      final x1 = row.map((b) => b.x + b.w).reduce(math.max);
      final y1 = row.map((b) => b.y + b.h).reduce(math.max);
      out.add(OcrLine(parts.join(' '), conf, x0, y0, x1 - x0, y1 - y0));
    }
    return out;
  }

  // ---------------------------------------------------------------- detector

  List<({int x, int y, int w, int h})> _detect(Bitmap img) {
    // Small regions are enlarged (tiny letters are not found otherwise),
    // huge ones reduced; the sides must be multiples of 32.
    final minSide = math.min(img.w, img.h), maxSide = math.max(img.w, img.h);
    var r = minSide < 160 ? math.min(4.0, 160 / minSide) : 1.0;
    if (maxSide * r > 1600) r = 1600 / maxSide;
    final nw = math.max(32, (img.w * r / 32).round() * 32);
    final nh = math.max(32, (img.h * r / 32).round() * 32);
    final input = toPlanes(img, 0, 0, img.w, img.h, nw, nh, nw);
    final prob = _det.run(input, [1, 3, nh, nw]).data;
    if (prob.length < nw * nh) return [];

    final seen = Uint8List(nw * nh);
    final stack = <int>[];
    final out = <({int x, int y, int w, int h})>[];
    for (var start = 0; start < nw * nh; start++) {
      if (seen[start] != 0 || prob[start] <= 0.3) continue;
      var x0 = nw, y0 = nh, x1 = 0, y1 = 0, n = 0;
      var sum = 0.0;
      seen[start] = 1;
      stack.add(start);
      while (stack.isNotEmpty) {
        final i = stack.removeLast();
        final x = i % nw, y = i ~/ nw;
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
        sum += prob[i];
        n++;
        for (var dy = -1; dy <= 1; dy++) {
          final yy = y + dy;
          if (yy < 0 || yy >= nh) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final xx = x + dx;
            if (xx < 0 || xx >= nw) continue;
            final j = yy * nw + xx;
            if (seen[j] == 0 && prob[j] > 0.3) {
              seen[j] = 1;
              stack.add(j);
            }
          }
        }
      }
      final bw = x1 - x0 + 1, bh = y1 - y0 + 1;
      if (math.min(bw, bh) < 3 || sum / n < 0.5) continue;
      // The model marks a shrunken core of the line: grow it back.
      final d = bw * bh * 1.5 / (2 * (bw + bh));
      final sx = img.w / nw, sy = img.h / nh;
      final left = ((x0 - d) * sx).floor().clamp(0, img.w - 1);
      final top = ((y0 - d) * sy).floor().clamp(0, img.h - 1);
      final right = ((x1 + 1 + d) * sx).ceil().clamp(left + 1, img.w);
      final bottom = ((y1 + 1 + d) * sy).ceil().clamp(top + 1, img.h);
      if (right - left < 4 || bottom - top < 4) continue;
      out.add((x: left, y: top, w: right - left, h: bottom - top));
    }
    return out;
  }

  // -------------------------------------------------------------- recognizer

  ({String text, double confidence}) _recognize(Bitmap img, int x, int y, int w, int h) {
    final rw = math.min(2400, math.max(8, (_recHeight * w / h).ceil()));
    final tw = math.max(_recMinWidth, rw);
    final input = toPlanes(img, x, y, w, h, rw, _recHeight, tw);
    final out = _rec.run(input, [1, 3, _recHeight, tw]);
    if (out.shape.length != 3) return (text: '', confidence: 0);
    return ctcDecode(out.data, out.shape[1], out.shape[2], _dict);
  }
}

/// Crop [x],[y],[w],[h] of [img] resized to [outW]x[outH] and written as
/// three float planes (B, G, R) in the range -1..1, each [padW] wide (the
/// rest stays 0), as PaddleOCR models expect.
Float32List toPlanes(Bitmap img, int x, int y, int w, int h, int outW, int outH, int padW) {
  final plane = padW * outH;
  final out = Float32List(3 * plane);
  final src = img.bgra;
  final sx = w / outW, sy = h / outH;
  final shrink = sx > 1.5 || sy > 1.5;
  for (var oy = 0; oy < outH; oy++) {
    for (var ox = 0; ox < outW; ox++) {
      double b, g, r;
      if (shrink) {
        // Average of the covered source pixels.
        final xa = x + (ox * sx).floor(), ya = y + (oy * sy).floor();
        final xb = math.min(x + w, math.max(xa + 1, x + ((ox + 1) * sx).ceil()));
        final yb = math.min(y + h, math.max(ya + 1, y + ((oy + 1) * sy).ceil()));
        var sb = 0, sg = 0, sr = 0;
        for (var py = ya; py < yb; py++) {
          var i = (py * img.w + xa) * 4;
          for (var px = xa; px < xb; px++, i += 4) {
            sb += src[i];
            sg += src[i + 1];
            sr += src[i + 2];
          }
        }
        final n = (xb - xa) * (yb - ya);
        b = sb / n;
        g = sg / n;
        r = sr / n;
      } else {
        final fx = ((ox + 0.5) * sx - 0.5).clamp(0.0, w - 1.0);
        final fy = ((oy + 0.5) * sy - 0.5).clamp(0.0, h - 1.0);
        final x0 = fx.floor(), y0 = fy.floor();
        final x1 = x0 + 1 < w ? x0 + 1 : x0, y1 = y0 + 1 < h ? y0 + 1 : y0;
        final wx = fx - x0, wy = fy - y0;
        final a = ((y + y0) * img.w + x + x0) * 4, c = ((y + y0) * img.w + x + x1) * 4;
        final d = ((y + y1) * img.w + x + x0) * 4, e = ((y + y1) * img.w + x + x1) * 4;
        double mix(int ch) =>
            (src[a + ch] * (1 - wx) + src[c + ch] * wx) * (1 - wy) +
            (src[d + ch] * (1 - wx) + src[e + ch] * wx) * wy;
        b = mix(0);
        g = mix(1);
        r = mix(2);
      }
      final o = oy * padW + ox;
      out[o] = b / 127.5 - 1;
      out[plane + o] = g / 127.5 - 1;
      out[2 * plane + o] = r / 127.5 - 1;
    }
  }
  return out;
}

/// Greedy CTC decoding of [t] steps x [c] classes with a Paddle dictionary
/// (class 0 is "blank", the class after the dictionary is a space).
({String text, double confidence}) ctcDecode(
    Float32List probs, int t, int c, List<String> dict) {
  final text = StringBuffer();
  var sum = 0.0, count = 0, last = -1;
  for (var step = 0; step < t; step++) {
    final row = step * c;
    var best = 0;
    for (var k = 1; k < c; k++) {
      if (probs[row + k] > probs[row + best]) best = k;
    }
    if (best != 0 && best != last) {
      final ch = best <= dict.length ? dict[best - 1] : (best == dict.length + 1 ? ' ' : '');
      if (ch.isNotEmpty) {
        text.write(ch);
        var p = probs[row + best].toDouble();
        if (p > 1 || p < 0) {
          // Raw scores: softmax of this row.
          var z = 0.0;
          for (var k = 0; k < c; k++) {
            z += math.exp(probs[row + k] - probs[row + best]);
          }
          p = 1 / z;
        }
        sum += p;
        count++;
      }
    }
    last = best;
  }
  return (text: text.toString(), confidence: count == 0 ? 0 : sum / count);
}
