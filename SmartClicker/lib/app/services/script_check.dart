// `smart_clicker.exe --check "Скрипт"`: checks a script without running it,
// so a neural network that wrote it learns about mistakes at once. The
// result goes to the console and to files\check.json; no window opens.

import 'dart:convert';
import 'dart:io';

import '../../core/lang/checker.dart';
import '../../core/lang/script_refs.dart';
import '../../core/storage/storage.dart';
import '../state/app_controller.dart' show AppController;

const checkArg = '--check';

/// The script named after `--check`, or null.
String? checkTarget(List<String> args) {
  final i = args.indexOf(checkArg);
  if (i < 0 || i + 1 >= args.length || args[i + 1].trim().isEmpty) return null;
  return args[i + 1].trim();
}

/// What the check found: {script, found, ok, checked, errors, warnings, issues:
/// [{line, message, error}]}. ok — no errors (warnings are allowed).
Map<String, Object?> checkReport(AppPaths paths, String want, {Set<String>? builtins}) {
  final all = ScriptStore(paths.scripts).all();
  final name = resolveScriptName(want, all.keys);
  if (name == null) {
    return {
      'script': want,
      'found': false,
      'ok': false,
      'checked': DateTime.now().toIso8601String(),
      'errors': 1,
      'warnings': 0,
      'issues': [
        {'line': 0, 'message': 'Скрипт «$want» не найден в папке scripts', 'error': true}
      ],
    };
  }
  bool imageExists(String n) {
    final file = n.toLowerCase().endsWith('.png') ? n : '$n.png';
    final abs = file.startsWith('/') || file.startsWith(r'\') || RegExp(r'^[A-Za-z]:').hasMatch(file);
    return File(abs ? file : '${paths.files}${Platform.pathSeparator}$file').existsSync();
  }

  final issues = checkScript(
    all[name]!,
    CheckContext(
      builtins: builtins ?? AppController.builtinNames,
      scriptSource: (n) => all[resolveScriptName(n, all.keys)],
      imageExists: imageExists,
      scriptNames: all.keys.toList(),
    ),
  );
  final errors = issues.where((i) => i.error).length;
  return {
    'script': name,
    'found': true,
    'ok': errors == 0,
    'checked': DateTime.now().toIso8601String(),
    'errors': errors,
    'warnings': issues.length - errors,
    'issues': [
      for (final i in issues) {'line': i.line, 'message': i.message, 'error': i.error}
    ],
  };
}

/// The report as lines for the console.
String checkText(Map<String, Object?> r) {
  final issues = (r['issues'] as List).cast<Map<String, Object?>>();
  if (issues.isEmpty) return 'Скрипт «${r['script']}»: ошибок не найдено';
  return [
    'Скрипт «${r['script']}»: ошибок ${r['errors']}, предупреждений ${r['warnings']}',
    for (final i in issues)
      '${i['error'] == true ? 'ошибка' : 'предупреждение'}, строка ${i['line']}: ${i['message']}',
  ].join('\n');
}

/// Runs the check, writes files\check.json and prints the result. Exit code:
/// 0 — no errors, 1 — errors or no such script.
int runCheckCommand(AppPaths paths, String want) {
  final r = checkReport(paths, want);
  try {
    final f = File('${paths.files}${Platform.pathSeparator}check.json')..parent.createSync(recursive: true);
    f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(r));
  } catch (_) {}
  stdout.writeln(checkText(r));
  return r['ok'] == true ? 0 : 1;
}
