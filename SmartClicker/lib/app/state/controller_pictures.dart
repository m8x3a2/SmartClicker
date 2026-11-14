// Saved pictures (files/*.png): where scripts use them, renaming with the
// scripts fixed, deleting, replacing a picture with a new snapshot.
part of 'app_controller.dart';

/// The mentions of a picture in one script.
class PictureUse {
  final String script;
  final List<PictureRef> refs;

  /// The mentions were found in text that is not saved yet.
  final bool unsaved;
  const PictureUse(this.script, this.refs, {this.unsaved = false});
}

extension AppControllerPictures on AppController {
  /// The text of a script as the user sees it (unsaved changes included).
  String _scriptText(String name) =>
      name == current ? editor.text : (buffers[name] ?? store.read(name));

  /// Scripts that mention picture [name], with the lines.
  List<PictureUse> pictureUses(String name) => [
        for (final s in scripts)
          if (findPictureRefs(_scriptText(s), name) case final refs when refs.isNotEmpty)
            PictureUse(s, refs, unsaved: isUnsaved(s)),
      ];

  /// Renames the picture file and, with [fix], the name in every script
  /// (on disk and in unsaved text). Returns an error or null.
  String? renamePicture(String old, String name, {required bool fix}) {
    final from = File(imagePath(old)), to = File(imagePath(name));
    if (!from.existsSync()) return 'Картинки «$old» нет';
    if (to.existsSync() && !samePictureName(old, name)) return 'Картинка «$name» уже есть';
    try {
      from.renameSync(to.path);
    } catch (e) {
      return 'Не получилось переименовать: $e';
    }
    if (fix) {
      for (final s in scripts) {
        String renamed(String text) => renamePictureRefs(text, findPictureRefs(text, old), name);
        final disk = store.read(s);
        final fixed = renamed(disk);
        if (fixed != disk) store.write(s, fixed);
        if (s == current) {
          final text = renamed(editor.text);
          _savedText = fixed;
          if (text != editor.text) _setEditor(text);
          dirty = editor.text != _savedText;
        } else if (buffers[s] case final b?) {
          buffers[s] = renamed(b);
        }
      }
    }
    picturesChanged.value++;
    _changed();
    return null;
  }

  String? deletePicture(String name) {
    try {
      File(imagePath(name)).deleteSync();
    } catch (e) {
      return 'Не получилось удалить: $e';
    }
    picturesChanged.value++;
    return null;
  }

  /// "Replace with a snapshot": mark a region on the screen (two Ctrl
  /// presses); it is saved over picture [name], the scripts stay as they are.
  void replacePicture(String name) {
    if (busy) return;
    _pictureToReplace = name;
    startPick('region');
    if (!picking) _pictureToReplace = null;
  }

  /// Called with the region marked for [replacePicture]. True if handled.
  bool _savePictureReplacement(Bitmap shot) {
    final name = _pictureToReplace;
    if (name == null) return false;
    _pictureToReplace = null;
    try {
      File(imagePath(name)).writeAsBytesSync(pngEncode(shot));
      notify('Картинка заменена', '«$name»: ${shot.w} × ${shot.h} px. Скрипты менять не нужно', level: 'ok');
    } catch (e) {
      notify('Картинка не заменена', '$e', level: 'warn');
    }
    picturesChanged.value++;
    return true;
  }

  /// Opens [script] in the editor with [line] shown (from "where used").
  void openScriptAt(String script, int line) {
    if (!store.exists(script)) return;
    open(script);
    openPage('scripts');
    revealLine.value = line;
  }
}
