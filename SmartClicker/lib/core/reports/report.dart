// Error reports (ZIP with script, log, variables, screenshot) and the journal
// of the program's own crashes.

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../vision/image.dart';
import '../storage/zip.dart';

/// Release builds on GitHub pass the tag: `--dart-define=APP_VERSION=1.2.0`.
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');

/// Errors of the program itself (bugs in SmartClicker, not in scripts).
/// They are appended to logs/app_errors.log and go into error reports.
class ErrorJournal {
  static String? path;

  /// Called after an error is written (the controller shows a notice).
  static void Function(String message)? onRecord;

  static const _maxBytes = 1 << 20;

  static void record(Object error, StackTrace? stack, {String where = ''}) {
    final p = path;
    if (p != null) {
      try {
        final f = File(p);
        f.parent.createSync(recursive: true);
        if (f.existsSync() && f.lengthSync() > _maxBytes) {
          // Too big: keep the newer half.
          final old = f.readAsStringSync();
          f.writeAsStringSync(old.substring(old.length ~/ 2));
        }
        final head = '${_stamp(DateTime.now())}${where.isEmpty ? '' : ' [$where]'}';
        f.writeAsStringSync('$head $error\n${stack ?? ''}\n',
            mode: FileMode.append);
      } catch (_) {
        // Nothing else can be done if even the journal fails.
      }
    }
    onRecord?.call('$error');
  }

  /// The last [lines] lines of the journal ('' when there were no errors).
  static String tail([int lines = 60]) {
    final p = path;
    if (p == null) return '';
    try {
      final all = const LineSplitter().convert(File(p).readAsStringSync());
      return all.skip(all.length > lines ? all.length - lines : 0).join('\n');
    } catch (_) {
      return '';
    }
  }
}

String _two(int n) => n.toString().padLeft(2, '0');

String _stamp(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)} '
    '${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';

/// Part of a file name: 2026-11-13_14-02-11.
String fileStamp(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}_'
    '${_two(d.hour)}-${_two(d.minute)}-${_two(d.second)}';

/// Source with line numbers, the way error messages count them.
String numbered(String source) {
  final lines = source.split('\n');
  final width = '${lines.length}'.length;
  return [
    for (var i = 0; i < lines.length; i++)
      '${'${i + 1}'.padLeft(width)} | ${lines[i].trimRight()}'
  ].join('\n');
}

/// Text of an error report: what happened, where, the scripts, the log and
/// the settings. Written so it can be pasted into a chat with an AI.
String reportText({
  required DateTime time,
  required String script,
  required String status,
  String? error,
  required Map<String, String> scripts,
  required String log,
  List<String> variables = const [],
  required Map<String, Object?> settings,
  required Map<String, String> environment,
  String appErrors = '',
  bool screenshot = false,
}) {
  final b = StringBuffer()
    ..writeln('ОТЧЁТ SMARTCLICKER')
    ..writeln('==================')
    ..writeln('Время: ${_stamp(time)}')
    ..writeln('Скрипт: $script')
    ..writeln('Итог: $status');
  if (error != null && error.isNotEmpty) b.writeln('Ошибка: $error');
  if (screenshot) {
    b.writeln('Снимок экрана в момент ошибки: screen.png (в этом же архиве)');
  }
  b
    ..writeln()
    ..writeln('СРЕДА')
    ..writeln('-----');
  environment.forEach((k, v) => b.writeln('$k: $v'));
  scripts.forEach((name, src) {
    final title = 'СКРИПТ "$name"';
    b
      ..writeln()
      ..writeln(title)
      ..writeln('-' * title.length)
      ..writeln(numbered(src));
  });
  b
    ..writeln()
    ..writeln('ЛОГ ЗАПУСКА')
    ..writeln('-----------')
    ..writeln(log.isEmpty ? '(пусто)' : log)
    ..writeln();
  if (variables.isNotEmpty) {
    b
      ..writeln('ПЕРЕМЕННЫЕ В КОНЦЕ ЗАПУСКА (в момент ошибки)')
      ..writeln('--------------------------------------------')
      ..writeAll(variables, '\n')
      ..writeln()
      ..writeln();
  }
  b
    ..writeln('НАСТРОЙКИ')
    ..writeln('---------')
    ..writeln(const JsonEncoder.withIndent('  ').convert(settings));
  if (appErrors.isNotEmpty) {
    b
      ..writeln()
      ..writeln('ОШИБКИ САМОЙ ПРОГРАММЫ (последние)')
      ..writeln('----------------------------------')
      ..writeln(appErrors);
  }
  return b.toString();
}

/// Packs the report (and the screenshot, if any) into one ZIP file. PNG
/// compression of a whole screen takes a moment, so it runs in an isolate.
Future<void> saveReport(String path, String text, Bitmap? shot) =>
    Isolate.run(() {
      final files = <String, List<int>>{'report.txt': utf8.encode(text)};
      if (shot != null) files['screen.png'] = pngEncode(shot);
      File(path).writeAsBytesSync(zipEncode(files));
    });

/// The text part of a saved report.
String readReportText(String path) {
  final files = zipDecode(File(path).readAsBytesSync(),
      only: (n) => n == 'report.txt');
  final t = files['report.txt'];
  if (t == null) throw const FormatException('в архиве нет report.txt');
  return utf8.decode(t, allowMalformed: true);
}

/// Keeps the newest [keep] files of [dir].
void pruneFolder(String dir, int keep) {
  try {
    final files = Directory(dir).listSync().whereType<File>().toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (final f in files.skip(keep)) {
      f.deleteSync();
    }
  } catch (_) {}
}

