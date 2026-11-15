// Scripts changed by other programs (a neural network, an editor): new and
// deleted files appear in the list, the open script shows the new text, or —
// with unsaved edits — the user chooses (see ExternalChangeBanner).
part of 'app_controller.dart';

extension AppControllerWatch on AppController {
  /// Called from the poll every 2 seconds.
  void _checkDiskChanges() {
    try {
      final list = store.list();
      final folders = store.folders();
      if (!_sameList(list, scripts) || !_sameList(folders, this.folders)) {
        scripts = list;
        this.folders = folders;
        _changed();
      }
      final name = current;
      if (name == null || !store.exists(name)) return;
      final disk = store.read(name);
      if (disk == _savedText || disk == externalText) return;
      if (!dirty) {
        _savedText = disk;
        _setEditor(disk);
        dirty = false;
        notify('Скрипт обновлён', '«$name» изменён другой программой — показан новый текст');
        _log('system', '↻ «$name» изменён на диске другой программой — текст обновлён');
        _changed();
      } else {
        // Unsaved edits here and a new text on disk: the user decides.
        externalText = disk;
        _changed();
      }
    } catch (e, s) {
      ErrorJournal.record(e, s, where: 'disk watch');
    }
  }

  /// "Take from disk": the text from disk replaces the unsaved edits (they
  /// stay in Ctrl+Z).
  void takeExternal() {
    final disk = externalText;
    if (disk == null || current == null) return;
    externalText = null;
    _savedText = disk;
    _setEditor(disk);
    dirty = false;
    _changed();
  }

  /// "Keep mine": the unsaved edits stay; Ctrl+S writes them over the disk.
  void keepMine() {
    final disk = externalText;
    if (disk == null) return;
    externalText = null;
    _savedText = disk;
    dirty = editor.text != _savedText;
    _changed();
  }

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
