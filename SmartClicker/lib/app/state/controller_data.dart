// The data folder: telling where it is and moving the data to another one
// (then the program restarts to use it).
part of 'app_controller.dart';

/// Copying runs in an isolate; the closure is made here, at the top level,
/// so it does not capture the controller.
Future<String?> _changeDataFolderInIsolate(
        String from, String to, DataMove mode, String standard, String exeDir) =>
    Isolate.run(() => changeDataFolder(
        from: from, to: to, mode: mode, standard: standard, exeDir: exeDir));

extension AppControllerData on AppController {
  /// Moves / copies the data to [to]; on success the program restarts.
  /// Returns an error text or null.
  Future<String?> changeDataFolderTo(String to, DataMove mode) async {
    if (busy) return 'Сначала остановите скрипт или запись';
    // Everything the user has must be on disk before it is copied.
    saveAll();
    saveSettings();
    final err = await _changeDataFolderInIsolate(paths.base, to, mode, standardDataDir(), exeDir());
    if (err != null) return err;
    if (!backend.restartSelf()) {
      notify('Папка с данными изменена', 'Перезапустите SmartClicker, чтобы он взял данные из $to',
          level: 'warn');
      return null;
    }
    await quit();
    return null;
  }

  /// At start: the chosen folder is not reachable (a drive not plugged in).
  void _warnUnreachableData() {
    final lost = paths.location.unreachable;
    if (lost == null) return;
    Timer.run(() => notify('Папка с данными недоступна',
        '$lost не найдена (флешка или диск не подключены?). Сейчас используются данные из ${paths.base}. '
            'Подключите диск и перезапустите программу',
        level: 'warn'));
  }
}
