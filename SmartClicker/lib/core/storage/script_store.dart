// Scripts as .cks files in folders: list, read, write, rename, check names.

import 'dart:io';

/// Scripts are plain `.cks` text files. A script name is its path relative
/// to the scripts folder, with `/` separators: `Примеры/Пример 1`.
class ScriptStore {
  final String dir;
  ScriptStore(this.dir);

  static const ext = '.cks';
  static final _sep = Platform.pathSeparator;

  static final _badChar = RegExp(r'[^\p{L}\p{N} _\-.()]', unicode: true);
  static final _reserved =
      RegExp(r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])$', caseSensitive: false);

  static List<String> _segments(String name) => name
      .replaceAll(r'\', '/')
      .split('/')
      .map((p) =>
          p.trim().replaceAll(RegExp(r'\.cks$', caseSensitive: false), '').trim())
      .where((p) => p.isNotEmpty)
      .toList();

  /// Checks a name typed by the user ("Имя" or "Папка/Имя"). Returns an
  /// error message for the user, or null when the name is fine.
  static String? validateName(String raw, {bool allowPath = true}) {
    final parts = _segments(raw);
    if (parts.isEmpty) return 'Введите имя';
    if (!allowPath && parts.length > 1) {
      return 'Здесь нужно одно имя, без «/»';
    }
    for (final part in parts) {
      final bad = _badChar.allMatches(part).map((m) => m.group(0)!).toSet();
      if (bad.isNotEmpty) {
        return 'Нельзя использовать: ${bad.join(' ')}\n'
            'Можно: буквы, цифры, пробел и _ - . ( )';
      }
      if (part == '.' || part == '..' || part.endsWith('.')) {
        return 'Имя не может состоять из точек или заканчиваться точкой';
      }
      if (_reserved.hasMatch(part)) {
        return '«$part» — служебное имя Windows, выберите другое';
      }
      if (part.length > 80) return 'Слишком длинное имя (больше 80 символов)';
    }
    return null;
  }

  /// Makes any name safe (used for imported files): bad characters become
  /// `_`. Keeps `/` as the folder separator.
  static String sanitize(String name) => _segments(name)
      .map((p) => p.replaceAll(_badChar, '_').replaceAll(RegExp(r'\.+$'), ''))
      .map((p) => _reserved.hasMatch(p) ? '${p}_' : p)
      .where((p) => p.isNotEmpty && p != '.' && p != '..')
      .join('/');

  static String folderOf(String name) =>
      name.contains('/') ? name.substring(0, name.lastIndexOf('/')) : '';
  static String baseOf(String name) => name.substring(name.lastIndexOf('/') + 1);

  String _native(String name) => '$dir$_sep${name.replaceAll('/', _sep)}';
  File _file(String name) => File('${_native(name)}$ext');
  String _rel(String path) =>
      path.substring(dir.length + 1).replaceAll(r'\', '/');

  List<String> list() {
    final d = Directory(dir);
    if (!d.existsSync()) return [];
    return d
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => _rel(f.path))
        .where((n) => n.toLowerCase().endsWith(ext))
        .map((n) => n.substring(0, n.length - ext.length))
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  List<String> folders() {
    final d = Directory(dir);
    if (!d.existsSync()) return [];
    return d
        .listSync(recursive: true)
        .whereType<Directory>()
        .map((f) => _rel(f.path))
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  bool exists(String name) => _file(name).existsSync();
  String read(String name) {
    try {
      return _file(name).readAsStringSync();
    } catch (_) {
      return '';
    }
  }

  void write(String name, String source) {
    final f = _file(name);
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(source);
  }

  void delete(String name) {
    final f = _file(name);
    if (f.existsSync()) f.deleteSync();
  }

  bool folderExists(String path) => Directory(_native(path)).existsSync();
  void createFolder(String path) =>
      Directory(_native(path)).createSync(recursive: true);

  /// Deletes a folder only when it is empty. Returns false otherwise.
  bool deleteFolder(String path) {
    final d = Directory(_native(path));
    if (!d.existsSync()) return true;
    if (d.listSync().isNotEmpty) return false;
    d.deleteSync();
    return true;
  }

  void renameFolder(String from, String to) {
    Directory(_native(to)).parent.createSync(recursive: true);
    Directory(_native(from)).renameSync(_native(to));
  }

  void deleteFolderRecursive(String path) {
    final d = Directory(_native(path));
    if (d.existsSync()) d.deleteSync(recursive: true);
  }

  /// Deletes every script, then the folders left empty. Other files that
  /// happen to lie in the scripts folder stay (with their folders).
  void deleteAll() {
    for (final n in list()) {
      delete(n);
    }
    final dirs = folders()..sort((a, b) => b.length.compareTo(a.length)); // deepest first
    for (final f in dirs) {
      deleteFolder(f);
    }
  }

  Map<String, String> all() => {for (final n in list()) n: read(n)};
}
