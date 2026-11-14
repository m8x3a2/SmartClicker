// Starting together with Windows: the switch in the settings and going to
// the tray right after such a start.
part of 'app_controller.dart';

extension AppControllerStartup on AppController {
  StartupInfo startupInfo() {
    final e = backend.startupEntry();
    return describeStartup(e.command,
        disabled: e.disabled, exe: Platform.resolvedExecutable);
  }

  void setStartWithWindows(bool on) {
    final ok = backend.setStartupEntry(on ? startupCommand(Platform.resolvedExecutable) : null);
    if (!ok) {
      notify('Не получилось', 'Windows не дал изменить список автозагрузки', level: 'warn');
    } else if (on) {
      notify('Запуск вместе с Windows',
          settings.autostartTray
              ? 'SmartClicker будет запускаться при входе в Windows и сразу сворачиваться в трей'
              : 'SmartClicker будет запускаться при входе в Windows',
          level: 'ok');
    }
    _changed();
  }

  /// Called from the poll: after a start at logon the window is hidden to
  /// the tray once it has appeared (it is shown after the first frame).
  void _hideAfterAutostart() {
    if (!startedWithWindows) return;
    if (!settings.autostartTray || _tick > 400) {
      startedWithWindows = false; // gave up after 10 s, or not wanted
      return;
    }
    if (!backend.isMainVisible()) return;
    startedWithWindows = false;
    _trayHintShown = true; // no balloon at every logon
    hideToTray();
  }
}
