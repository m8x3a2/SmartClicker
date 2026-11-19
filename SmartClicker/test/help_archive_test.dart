// «Выгрузить всю справку в ZIP»: every guide and the prompt for an AI chat.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/app/help/help_texts.dart';
import 'package:smart_clicker/app/ui/help/help_screen.dart';
import 'package:smart_clicker/core/storage/storage.dart';
import 'package:smart_clicker/core/storage/zip.dart';

void main() {
  test('help archive: one .md per guide plus the AI prompt', () {
    final tmp = Directory.systemTemp.createTempSync('sc_help_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final files = helpArchive(AppPaths(tmp.path));
    final guides = helpSections.where((s) => s.text != null).length;
    expect(files.length, guides + 1);
    expect(files.keys.every((k) => k.endsWith('.md') && !k.contains(':')), isTrue);
    expect(files.keys.first, startsWith('01 '));
    final prompt = utf8.decode(files['Промпт для ИИ.md']!);
    expect(prompt, contains('ПРОГРАММА: ГДЕ ЧТО НАЖАТЬ'));
    expect(prompt, contains(languageReference.trim().split('\n').first));
    // the archive opens again
    final back = zipDecode(zipEncode(files));
    expect(back.keys.toSet(), files.keys.toSet());
  });
}
