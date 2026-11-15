// Full backup of the data, restoring it and "reset everything": the last two
// replace the data folder and restart the program at once.
part of 'app_controller.dart';

/// The backup bytes in an isolate (the closure is made here, at the top
/// level, so it does not take the controller along).
Future<Uint8List> _autoBackupBytes(String dir, Map<String, String> scripts) =>
    Isolate.run(() => makeBackup(dir, scripts: scripts));

extension AppControllerBackup on AppController {
  /// Daily automatic backup: called from the poll (half a minute after the
  /// start, then every hour — the program may run over midnight).
  Future<void> _checkAutoBackup() async {
    if (!settings.autoBackup || _autoBackupBusy) return;
    final dir = Directory(paths.autoBackups);
    final names = dir.existsSync()
        ? [for (final f in dir.listSync().whereType<File>()) f.uri.pathSegments.last]
        : <String>[];
    final now = DateTime.now();
    if (!autoBackupDue(names, now)) return;
    _autoBackupBusy = true;
    try {
      final bytes = await _autoBackupBytes(paths.base, _allScriptTexts());
      dir.createSync(recursive: true);
      final name = autoBackupName(now);
      final tmp = File('${dir.path}${Platform.pathSeparator}$name.tmp');
      tmp.writeAsBytesSync(bytes);
      tmp.renameSync('${dir.path}${Platform.pathSeparator}$name');
      for (final old in autoBackupsToDelete([...names, name], settings.autoBackupKeep)) {
        try {
          File('${dir.path}${Platform.pathSeparator}$old').deleteSync();
        } catch (_) {}
      }
      _log('system', '💾 Ежедневная копия данных: $name');
    } catch (e, s) {
      ErrorJournal.record(e, s, where: 'auto backup');
    } finally {
      _autoBackupBusy = false;
    }
  }

  /// The copies made by the daily backup, newest first.
  List<String> autoBackupFiles() {
    final dir = Directory(paths.autoBackups);
    if (!dir.existsSync()) return const [];
    return autoBackupsIn([for (final f in dir.listSync().whereType<File>()) f.uri.pathSegments.last]);
  }

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
    markCleanExit();
    backend.restartSelf();
    backend.hideTray();
    backend.stopKeyHook();
    backend.releaseAll();
    backend.endProcess();
  }
}
