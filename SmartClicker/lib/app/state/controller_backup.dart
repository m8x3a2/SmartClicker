// Full backup of the data, restoring it and "reset everything": the last two
// replace the data folder and restart the program at once.
part of 'app_controller.dart';

extension AppControllerBackup on AppController {
  /// Saves a backup of everything into a ZIP chosen by the user.
  /// Returns true if it was saved.
  bool saveBackup() {
    String two(int n) => n.toString().padLeft(2, '0');
    final d = DateTime.now();
    final path = backend.pickFile(
        save: true,
        title: 'Резервная копия SmartClicker',
        defaultName: 'SmartClicker-копия-${d.year}-${two(d.month)}-${two(d.day)}.zip');
    if (path == null) return false;
    try {
      // Unsaved edits are in the backup too: what you see is what is saved.
      File(path).writeAsBytesSync(makeBackup(paths.base, scripts: _allScriptTexts()));
      final info = countData(paths.base);
      notify('Резервная копия готова',
          '${info.describe()}, а также настройки, расписание, автозапуск, история\n$path',
          level: 'ok');
      return true;
    } catch (e) {
      notify('Не удалось сохранить копию', '$e', level: 'error');
      return false;
    }
  }

  /// Asks for a backup and reads it; null if cancelled or not a backup.
  ({Map<String, Uint8List> files, BackupInfo info})? openBackup() {
    final path = backend.pickFile(save: false, title: 'Восстановить из резервной копии');
    if (path == null) return null;
    try {
      return readBackup(Uint8List.fromList(File(path).readAsBytesSync()));
    } catch (e) {
      notify('Не удалось прочитать копию', e is FormatException ? e.message : '$e', level: 'error');
      return null;
    }
  }

  /// Replaces all data with the backup [files] and restarts.
  void restoreFromBackup(Map<String, Uint8List> files) {
    if (busy) return;
    try {
      restoreBackup(paths.base, files);
    } catch (e) {
      notify('Не удалось восстановить', '$e', level: 'error');
      return;
    }
    _restartNow();
  }

  /// Deletes everything of the program (but the OCR models) and restarts:
  /// it starts as just installed, with the examples.
  void resetEverything() {
    if (busy) return;
    try {
      resetData(paths.base);
    } catch (e) {
      notify('Сброс не удался', '$e', level: 'error');
      return;
    }
    _restartNow();
  }

  /// The data on disk was replaced: nothing may be written any more (no
  /// settings, no unsaved scripts), so the program ends right away and a new
  /// copy starts.
  void _restartNow() {
    backend.restartSelf();
    backend.hideTray();
    backend.stopKeyHook();
    backend.releaseAll();
    backend.endProcess();
  }
}
