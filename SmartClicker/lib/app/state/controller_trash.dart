// Trash of deleted scripts, folders and pictures: put back (a taken name
// gets « (восстановлен)»), delete for good, empty; older than 30 days goes
// by itself at the start. Storage — core/storage/trash.dart.
part of 'app_controller.dart';

extension AppControllerTrash on AppController {
  Trash get trash => _trash ??= (Trash(paths.trash)..load());

  /// Called once at the start: what is older than 30 days goes for good.
  void _purgeTrash() {
    try {
      trash.purgeOld(DateTime.now());
    } catch (e, s) {
      ErrorJournal.record(e, s, where: 'trash');
    }
  }

  /// A script goes to the trash; [unsaved] — its text on the screen, if it
  /// had edits that were not saved (they are kept, not lost).
  void _scriptToTrash(String name, String? unsaved) {
    try {
      trash.put('script', name, store.pathOf(name), text: unsaved);
    } catch (e) {
      notify('Не удалось удалить', '$e', level: 'error');
    }
  }

  /// A free name like [name]: «Бой», «Бой (восстановлен)», «Бой (восстановлен 2)».
  static String _freeName(String name, bool Function(String) taken) {
    if (!taken(name)) return name;
    for (var i = 1;; i++) {
      final n = i == 1 ? '$name (восстановлен)' : '$name (восстановлен $i)';
      if (!taken(n)) return n;
    }
  }

  /// Puts [e] back where it was. Returns what to tell the user.
  String restoreFromTrash(TrashEntry e) {
    final item = trash.itemOf(e);
    if (item == null) {
      trash.forget(e);
      _changed();
      return 'В корзине нет файла — запись убрана';
    }
    var where = e.name;
    try {
      switch (e.kind) {
        case 'script':
          where = _freeName(e.name, store.exists);
          final to = File(store.pathOf(where));
          to.parent.createSync(recursive: true);
          (item as File).copySync(to.path);
        case 'picture':
          where = _freeName(e.name, (n) => File(imagePath(n)).existsSync());
          (item as File).copySync(imagePath(where));
          picturesChanged.value++;
        default: // a folder or all scripts: merged back, taken names renamed
          _mergeBack(item as Directory, e.name.isEmpty ? paths.scripts : store.folderPathOf(e.name));
          where = e.name.isEmpty ? 'список скриптов' : e.name;
      }
    } catch (err) {
      return 'Не получилось вернуть: $err';
    }
    trash.forget(e);
    _refresh();
    _changed();
    return where == e.name || e.kind == 'folder' ? 'Возвращено: $where' : 'Возвращено как «$where» (имя было занято)';
  }

  void _mergeBack(Directory src, String dst) {
    for (final f in src.listSync(recursive: true).whereType<File>()) {
      var rel = f.path.substring(src.path.length);
      var to = File('$dst$rel');
      if (to.existsSync()) {
        final dot = rel.lastIndexOf('.');
        final stem = dot > 0 ? rel.substring(0, dot) : rel;
        final ext = dot > 0 ? rel.substring(dot) : '';
        var i = 1;
        do {
          to = File('$dst$stem${i == 1 ? ' (восстановлен)' : ' (восстановлен $i)'}$ext');
          i++;
        } while (to.existsSync());
      }
      to.parent.createSync(recursive: true);
      f.copySync(to.path);
    }
  }

  void deleteForever(TrashEntry e) {
    trash.forget(e);
    _changed();
  }

  void emptyTrash() {
    trash.clear();
    _changed();
  }
}
