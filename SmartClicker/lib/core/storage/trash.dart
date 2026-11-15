// Trash of deleted scripts, folders and pictures (the data folder `trash\`):
// what is deleted is moved here and can be put back for 30 days; older
// items go by themselves, or all at once with «Очистить корзину».

import 'dart:convert';
import 'dart:io';

/// How many days the trash keeps a deleted item.
const trashDays = 30;

class TrashEntry {
  final String id;

  /// 'script', 'folder' (name '' — all scripts at once) or 'picture'.
  final String kind;

  /// Where it was: the name of the script ("Папка/Бой"), the folder path,
  /// the picture name (without .png).
  final String name;
  final DateTime deletedAt;

  /// Scripts inside (for a folder).
  final int count;

  const TrashEntry(this.id, this.kind, this.name, this.deletedAt, {this.count = 1});

  factory TrashEntry.fromJson(Map j) => TrashEntry(
        '${j['id']}',
        '${j['kind']}',
        '${j['name'] ?? ''}',
        DateTime.tryParse('${j['deletedAt']}') ?? DateTime.now(),
        count: (j['count'] as num?)?.toInt() ?? 1,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind,
        'name': name,
        'deletedAt': deletedAt.toIso8601String(),
        'count': count,
      };

  /// Words for the list.
  String get title => switch (kind) {
        'folder' => name.isEmpty ? 'Все скрипты ($count)' : 'Папка «$name» ($count)',
        'picture' => 'Картинка «$name»',
        _ => 'Скрипт «$name»',
      };

  /// Days left before it goes for good.
  int daysLeft(DateTime now) => trashDays - now.difference(deletedAt).inDays;
}

class Trash {
  final String dir;
  final List<TrashEntry> entries = []; // newest first
  Trash(this.dir);

  static final _sep = Platform.pathSeparator;
  String get _index => '$dir${_sep}index.json';

  /// Where the thing itself lies in the trash.
  String payload(TrashEntry e) => '$dir$_sep${e.id}';

  void load() {
    entries.clear();
    try {
      final f = File(_index);
      if (!f.existsSync()) return;
      final d = jsonDecode(f.readAsStringSync());
      if (d is List) entries.addAll(d.whereType<Map>().map(TrashEntry.fromJson));
    } catch (_) {}
  }

  void save() {
    try {
      Directory(dir).createSync(recursive: true);
      final tmp = File('$_index.tmp');
      tmp.writeAsStringSync(jsonEncode(entries.map((e) => e.toJson()).toList()));
      tmp.renameSync(_index);
    } catch (_) {}
  }

  /// Moves [from] (a file or a folder) into the trash. [text] — for a script
  /// with unsaved edits: the text that was on the screen is kept instead.
  TrashEntry put(String kind, String name, String from,
      {int count = 1, String? text, DateTime? now}) {
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final to = payload(TrashEntry(id, kind, name, DateTime.now()));
    Directory(to).createSync(recursive: true);
    final base = from.substring(from.lastIndexOf(_sep) + 1);
    final target = '$to$_sep$base';
    final type = FileSystemEntity.typeSync(from);
    if (type == FileSystemEntityType.directory) {
      _move(Directory(from), target);
    } else if (type == FileSystemEntityType.file) {
      if (text != null) {
        File(target).writeAsStringSync(text);
        File(from).deleteSync();
      } else {
        _moveFile(File(from), target);
      }
    } else if (text != null) {
      File(target).writeAsStringSync(text); // only on the screen, never saved
    }
    final e = TrashEntry(id, kind, name, now ?? DateTime.now(), count: count);
    entries.insert(0, e);
    save();
    return e;
  }

  /// The thing of [e] (a file or a folder inside its payload folder).
  FileSystemEntity? itemOf(TrashEntry e) {
    final d = Directory(payload(e));
    if (!d.existsSync()) return null;
    final list = d.listSync();
    return list.isEmpty ? null : list.first;
  }

  /// Takes [e] out of the trash (the caller has put the thing back).
  void forget(TrashEntry e) {
    entries.remove(e);
    _delete(payload(e));
    save();
  }

  /// Deletes for good everything older than [trashDays].
  int purgeOld(DateTime now) {
    final old = entries.where((e) => e.daysLeft(now) <= 0).toList();
    for (final e in old) {
      entries.remove(e);
      _delete(payload(e));
    }
    if (old.isNotEmpty) save();
    return old.length;
  }

  void clear() {
    for (final e in entries) {
      _delete(payload(e));
    }
    entries.clear();
    save();
  }

  static void _delete(String path) {
    try {
      final d = Directory(path);
      if (d.existsSync()) d.deleteSync(recursive: true);
    } catch (_) {}
  }

  static void _moveFile(File f, String to) {
    try {
      f.renameSync(to);
    } on FileSystemException {
      f.copySync(to); // another drive
      f.deleteSync();
    }
  }

  static void _move(Directory d, String to) {
    try {
      d.renameSync(to);
    } on FileSystemException {
      Directory(to).createSync(recursive: true);
      for (final e in d.listSync(recursive: true)) {
        final rel = e.path.substring(d.path.length);
        if (e is Directory) {
          Directory('$to$rel').createSync(recursive: true);
        } else if (e is File) {
          File('$to$rel').parent.createSync(recursive: true);
          e.copySync('$to$rel');
        }
      }
      d.deleteSync(recursive: true);
    }
  }
}
