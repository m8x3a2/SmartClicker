// History of the clipboard (like Win+V, but longer and with files): what was
// copied — text, files, pictures — kept in the data folder `clipboard\`
// (index.json + pictures as .png), with limits on count and size.

import 'dart:convert';
import 'dart:io';

/// One copied thing.
class ClipItem {
  final String id;

  /// 'text', 'files' or 'image'.
  final String kind;
  final String? text;
  final List<String>? files;

  /// The .png of a picture (in the history folder) and its size.
  final String? image;
  final int w, h;

  /// Bytes it takes: the text, or the .png (files are only paths).
  final int bytes;
  final DateTime at;
  bool pinned;

  ClipItem({
    required this.id,
    required this.kind,
    this.text,
    this.files,
    this.image,
    this.w = 0,
    this.h = 0,
    required this.bytes,
    required this.at,
    this.pinned = false,
  });

  factory ClipItem.fromJson(Map j) => ClipItem(
        id: '${j['id']}',
        kind: '${j['kind']}',
        text: j['text'] as String?,
        files: (j['files'] as List?)?.map((e) => '$e').toList(),
        image: j['image'] as String?,
        w: (j['w'] as num?)?.toInt() ?? 0,
        h: (j['h'] as num?)?.toInt() ?? 0,
        bytes: (j['bytes'] as num?)?.toInt() ?? 0,
        at: DateTime.tryParse('${j['at']}') ?? DateTime.now(),
        pinned: j['pinned'] == true,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind,
        if (text != null) 'text': text,
        if (files != null) 'files': files,
        if (image != null) 'image': image,
        if (w > 0) 'w': w,
        if (h > 0) 'h': h,
        'bytes': bytes,
        'at': at.toIso8601String(),
        if (pinned) 'pinned': true,
      };

  /// One line for the list.
  String get title => switch (kind) {
        'files' => files!.length == 1
            ? files!.first.split(RegExp(r'[\\/]')).last
            : '${files!.length} файлов: ${files!.map((f) => f.split(RegExp(r'[\\/]')).last).take(3).join(', ')}'
                '${files!.length > 3 ? '…' : ''}',
        'image' => 'Картинка $w×$h',
        _ => text!.replaceAll(RegExp(r'\s+'), ' ').trim(),
      };

  /// Same content as [other] (copying the same twice keeps one item).
  bool sameAs(ClipItem other) =>
      kind == other.kind &&
      text == other.text &&
      (files ?? const []).join('\n') == (other.files ?? const []).join('\n') &&
      (kind != 'image' || (w == other.w && h == other.h && bytes == other.bytes));
}

class ClipHistory {
  /// The folder: index.json and the pictures.
  final String dir;
  final List<ClipItem> items = []; // newest first

  /// Pasted in the "one by one" mode (newest first): can be put back.
  final List<ClipItem> trash = [];

  /// How many items the trash keeps.
  static const trashSize = 100;
  ClipHistory(this.dir);

  String get _index => '$dir${Platform.pathSeparator}index.json';
  String imagePath(ClipItem i) => '$dir${Platform.pathSeparator}${i.image}';

  void load() {
    items.clear();
    trash.clear();
    try {
      final f = File(_index);
      if (!f.existsSync()) return;
      final d = jsonDecode(f.readAsStringSync());
      if (d is List) items.addAll(d.whereType<Map>().map(ClipItem.fromJson)); // older index
      if (d is Map) {
        items.addAll((d['items'] as List? ?? const []).whereType<Map>().map(ClipItem.fromJson));
        trash.addAll((d['trash'] as List? ?? const []).whereType<Map>().map(ClipItem.fromJson));
      }
    } catch (_) {
      // A broken index: start empty (pictures stay on disk until cleared).
    }
  }

  void save() {
    try {
      Directory(dir).createSync(recursive: true);
      final tmp = File('$_index.tmp');
      tmp.writeAsStringSync(jsonEncode({
        'items': items.map((i) => i.toJson()).toList(),
        'trash': trash.map((i) => i.toJson()).toList(),
      }));
      tmp.renameSync(_index);
    } catch (_) {}
  }

  int get totalBytes => items.fold(0, (s, i) => s + i.bytes);

  static String newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  /// Adds [item] on top; the same thing copied again just moves up.
  /// Then the oldest unpinned ones go until the limits hold.
  void add(ClipItem item, {required int maxItems, required int maxBytes}) {
    final same = items.indexWhere((i) => i.sameAs(item));
    if (same >= 0) {
      final old = items.removeAt(same);
      if (item.image != null && item.image != old.image) _deleteImage(item);
      items.insert(0, old);
    } else {
      items.insert(0, item);
    }
    trim(maxItems: maxItems, maxBytes: maxBytes);
    save();
  }

  void trim({required int maxItems, required int maxBytes}) {
    var count = items.length, bytes = totalBytes;
    // The newest one stays (it was just copied) — unless it alone is too big.
    for (var i = items.length - 1; i >= 1 && (count > maxItems || bytes > maxBytes); i--) {
      if (items[i].pinned) continue;
      final gone = items.removeAt(i);
      _deleteImage(gone);
      count--;
      bytes -= gone.bytes;
    }
    if (items.isNotEmpty && !items.first.pinned && items.first.bytes > maxBytes) {
      _deleteImage(items.removeAt(0));
    }
  }

  void remove(ClipItem item) {
    items.remove(item);
    _deleteImage(item);
    save();
  }

  /// Removes everything except the pinned ones.
  void clear() {
    for (final i in items.where((i) => !i.pinned).toList()) {
      items.remove(i);
      _deleteImage(i);
    }
    save();
  }

  /// The item the "one by one" mode pastes next: the oldest unpinned one
  /// (things are pasted in the order they were copied).
  ClipItem? get nextInLine {
    for (final i in items.reversed) {
      if (!i.pinned) return i;
    }
    return null;
  }

  /// Pasted: the item goes to the trash (the trash keeps [trashSize]).
  void toTrash(ClipItem i) {
    if (!items.remove(i)) return;
    trash.insert(0, i);
    while (trash.length > trashSize) {
      _deleteImage(trash.removeLast());
    }
    save();
  }

  /// Back from the trash, on top of the history.
  void restore(ClipItem i) {
    if (!trash.remove(i)) return;
    items.insert(0, i);
    save();
  }

  void emptyTrash() {
    for (final i in trash) {
      _deleteImage(i);
    }
    trash.clear();
    save();
  }

  void _deleteImage(ClipItem i) {
    if (i.image == null) return;
    try {
      File(imagePath(i)).deleteSync();
    } catch (_) {}
  }
}
