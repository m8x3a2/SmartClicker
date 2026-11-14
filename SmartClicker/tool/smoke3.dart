// ignore_for_file: avoid_print
// Checks keyboard-layout detection in an already open Notepad window.
// Only switches focus to it and back; nothing is typed.
// Run: dart run tool/smoke3.dart
import 'dart:io';

import 'package:smart_clicker/platform/windows/windows_backend.dart';

Future<void> main() async {
  final b = WindowsBackend();
  final before = b.activeWindow();
  print('now active: ${before?.process} | ${b.layoutDebug()}');
  final notepads =
      b.windows().where((w) => w.process.toLowerCase() == 'notepad.exe').toList();
  print('notepad windows: ${notepads.map((w) => w.title).toList()}');
  if (notepads.isEmpty) exit(0);
  b.focusWindow(notepads.first.handle);
  await Future<void>.delayed(const Duration(milliseconds: 700));
  print('active: ${b.activeWindow()?.process} | ${b.layoutDebug()}');
  print('G -> ${b.charForVk(0x47, shift: false)}');
  if (before != null) b.focusWindow(before.handle);
  exit(0);
}
