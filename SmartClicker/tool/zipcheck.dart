// ignore_for_file: avoid_print
// Writes a ZIP with our encoder (arg 1) / lists a ZIP with our decoder (arg 2).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:smart_clicker/core/storage/zip.dart';

void main(List<String> args) {
  if (args[0] == 'write') {
    File(args[1]).writeAsBytesSync(zipEncode({
      'Примеры/Пример 1.cks': utf8.encode('click(50%, 50%)\nwait(1s)\n'),
      'корень.cks': utf8.encode('log("привет")\n'),
    }));
    print('written');
  } else {
    final files = zipDecode(Uint8List.fromList(File(args[1]).readAsBytesSync()));
    files.forEach((k, v) => print('$k => ${utf8.decode(v).trim()}'));
  }
}
