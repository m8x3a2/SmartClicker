// Downloads the files of the accurate text recognition (PaddleOCR): two
// models, a dictionary and the ONNX Runtime library. Runs only when the user
// presses the install button; every file is checked by SHA-256.

import 'dart:io';
import 'dart:typed_data';

import '../../core/vision/paddle_ocr.dart';
import '../../core/storage/zip.dart';

class OcrDownload {
  final String name, url, sha256;
  final int size;

  /// Path inside the downloaded ZIP (NuGet package) when the file is packed.
  final String? inZip;
  const OcrDownload(this.name, this.url, this.sha256, this.size, {this.inZip});
}

const _hf = 'https://huggingface.co/ogkalu/ppocr-v5-onnx/resolve/main';

const paddleDownloads = <OcrDownload>[
  OcrDownload(paddleDetModel, '$_hf/$paddleDetModel',
      '4d97c44a20d30a81aad087d6a396b08f786c4635742afc391f6621f5c6ae78ae', 4819576),
  OcrDownload(paddleRecModel, '$_hf/$paddleRecModel',
      '08705d6721849b1347d26187f15a5e362c431963a2a62bfff4feac578c489aab', 7911802),
  OcrDownload(paddleDict, '$_hf/$paddleDict',
      '3e95f1581557162870cacdba5af91a4c6be2890710d395b0c3c7578e7ee5e6eb', 1663),
  // Official ONNX Runtime 1.24.4 from NuGet (the package is a ZIP).
  OcrDownload(
      'onnxruntime.dll',
      'https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime.directml/1.24.4/'
          'microsoft.ml.onnxruntime.directml.1.24.4.nupkg',
      '57e9f11b73437bef7a309496135d4c1f96b1a8e9ddba60013fa27bfc1d788681',
      12458649,
      inZip: 'runtimes/win-x64/native/onnxruntime.dll'),
];

/// Megabytes that still have to be downloaded into [dir].
int paddleDownloadMb(String dir) {
  final lost = PaddleOcr.missing(dir);
  final bytes = paddleDownloads
      .where((d) => lost.contains(d.name))
      .fold<int>(0, (a, d) => a + d.size);
  return (bytes / 1048576).ceil();
}

/// Downloads what is missing. [progress] gets 0..1 and the current file.
Future<void> installPaddle(String dir,
    void Function(double done, String file) progress) async {
  Directory(dir).createSync(recursive: true);
  final lost = PaddleOcr.missing(dir);
  final todo = paddleDownloads.where((d) => lost.contains(d.name)).toList();
  final total = todo.fold<int>(0, (a, d) => a + d.size);
  var before = 0;
  final client = HttpClient()..findProxy = HttpClient.findProxyFromEnvironment;
  try {
    for (final d in todo) {
      final target = File('$dir${Platform.pathSeparator}${d.name}');
      final part = File('${target.path}.part');
      // A slow or unstable connection: every file gets several attempts.
      for (var attempt = 1;; attempt++) {
        final hash = Sha256();
        final sink = part.openWrite();
        var got = 0;
        try {
          final response = await (await client.getUrl(Uri.parse(d.url))).close();
          if (response.statusCode != 200) {
            throw HttpException('сервер ответил ${response.statusCode}',
                uri: Uri.parse(d.url));
          }
          await for (final chunk in response) {
            sink.add(chunk);
            hash.add(chunk);
            got += chunk.length;
            progress(total == 0 ? 1 : (before + got) / total, d.name);
          }
          await sink.close();
          if (hash.hex() != d.sha256) {
            throw FormatException('файл ${d.name} скачался с ошибкой '
                '(не сошлась контрольная сумма)');
          }
          break;
        } catch (e) {
          try {
            await sink.close();
          } catch (_) {}
          if (part.existsSync()) part.deleteSync();
          if (attempt >= 4) {
            throw Exception('не удалось скачать ${d.name} — проверьте интернет '
                'и нажмите ещё раз (уже скачанное сохранится). Причина: $e');
          }
          await Future<void>.delayed(Duration(seconds: attempt * 2));
        }
      }
      if (d.inZip != null) {
        final files = zipDecode(part.readAsBytesSync(), only: (n) => n == d.inZip);
        final data = files[d.inZip];
        part.deleteSync();
        if (data == null) throw FormatException('в пакете нет ${d.inZip}');
        target.writeAsBytesSync(data);
      } else {
        if (target.existsSync()) target.deleteSync();
        part.renameSync(target.path);
      }
      before += d.size;
    }
  } finally {
    client.close(force: true);
  }
}

List<String> get _paddleFiles =>
    [paddleRuntime, paddleDetModel, paddleRecModel, paddleDict];

/// Installs from a ZIP made by [exportPaddleZip] (or packed by hand: the
/// four files, in any folder of the archive). Returns the files still missing.
List<String> importPaddleZip(String dir, String zipPath) {
  Directory(dir).createSync(recursive: true);
  String base(String n) => n.replaceAll('\\', '/').split('/').last;
  final files = zipDecode(File(zipPath).readAsBytesSync(),
      only: (n) => _paddleFiles.contains(base(n)));
  for (final e in files.entries) {
    File('$dir${Platform.pathSeparator}${base(e.key)}').writeAsBytesSync(e.value);
  }
  return PaddleOcr.missing(dir);
}

/// Packs the installed files into one ZIP to carry to another computer.
void exportPaddleZip(String dir, String zipPath) {
  File(zipPath).writeAsBytesSync(zipEncode({
    for (final f in _paddleFiles)
      f: File('$dir${Platform.pathSeparator}$f').readAsBytesSync(),
  }));
}

/// Streaming SHA-256 (no packages needed).
class Sha256 {
  static const _k = <int>[
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
    0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];
  final _h = Uint32List.fromList([
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  ]);
  final _block = Uint8List(64);
  final _w = Uint32List(64);
  int _fill = 0, _length = 0;

  void add(List<int> data) {
    _length += data.length;
    for (final b in data) {
      _block[_fill++] = b;
      if (_fill == 64) {
        _compress();
        _fill = 0;
      }
    }
  }

  static int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xFFFFFFFF;

  void _compress() {
    final w = _w;
    for (var i = 0; i < 16; i++) {
      w[i] = (_block[i * 4] << 24) |
          (_block[i * 4 + 1] << 16) |
          (_block[i * 4 + 2] << 8) |
          _block[i * 4 + 3];
    }
    for (var i = 16; i < 64; i++) {
      final s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xFFFFFFFF;
    }
    var a = _h[0], b = _h[1], c = _h[2], d = _h[3];
    var e = _h[4], f = _h[5], g = _h[6], h = _h[7];
    for (var i = 0; i < 64; i++) {
      final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final ch = (e & f) ^ ((~e & 0xFFFFFFFF) & g);
      final t1 = (h + s1 + ch + _k[i] + w[i]) & 0xFFFFFFFF;
      final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (s0 + maj) & 0xFFFFFFFF;
      h = g;
      g = f;
      f = e;
      e = (d + t1) & 0xFFFFFFFF;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & 0xFFFFFFFF;
    }
    _h[0] += a;
    _h[1] += b;
    _h[2] += c;
    _h[3] += d;
    _h[4] += e;
    _h[5] += f;
    _h[6] += g;
    _h[7] += h;
  }

  /// Finishes the hash and returns it as lower-case hex.
  String hex() {
    final bits = _length * 8;
    final pad = <int>[0x80];
    while ((_fill + pad.length) % 64 != 56) {
      pad.add(0);
    }
    for (var i = 7; i >= 0; i--) {
      pad.add((bits >> (i * 8)) & 0xFF);
    }
    final keep = _length;
    add(pad);
    _length = keep;
    return _h.map((v) => v.toRadixString(16).padLeft(8, '0')).join();
  }
}
