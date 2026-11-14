// Checks the "start with Windows" entry in the real registry and puts back
// whatever was there before.   dart run tool/smoke_startup.dart
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:smart_clicker/core/system/startup.dart';
import 'package:smart_clicker/platform/windows/windows_backend.dart';

void main() {
  final b = WindowsBackend();
  final before = b.startupEntry();
  print('before: command=${before.command} disabled=${before.disabled}');
  var ok = true;
  void check(String what, bool cond) {
    print('${cond ? 'OK  ' : 'FAIL'} $what');
    ok &= cond;
  }

  const exe = r'C:\SmartClicker smoke test\smart_clicker.exe';
  try {
    check('write', b.setStartupEntry(startupCommand(exe)));
    final e = b.startupEntry();
    check('read back: ${e.command}', e.command == startupCommand(exe) && !e.disabled);
    check('described as this exe', describeStartup(e.command, disabled: e.disabled, exe: exe).active);
    check('remove', b.setStartupEntry(null));
    check('gone', b.startupEntry().command == null);
    check('remove again is fine', b.setStartupEntry(null));
  } finally {
    // The user's own entry comes back. A Task Manager "off" flag is lost
    // only if the entry was ours and turned off — then it stays on.
    if (before.command != null) b.setStartupEntry(before.command);
    final after = b.startupEntry();
    print('after: command=${after.command} disabled=${after.disabled}');
  }
  print(ok ? 'ALL OK' : 'SOME CHECKS FAILED');
  exit(ok ? 0 : 1);
}
