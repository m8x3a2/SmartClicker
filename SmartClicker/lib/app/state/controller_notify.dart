// Notifications, toasts and the log of the run.
part of 'app_controller.dart';

extension AppControllerNotify on AppController {
  void notify(String title, String body, {String level = 'info'}) {
    // The window is hidden: tell it next to the tray icon instead.
    if (hiddenToTray && level != 'info') backend.trayBalloon(title, body);
    final n = AppNotification(DateTime.now(), title, body, level);
    notifications.insert(0, n);
    if (notifications.length > 200) notifications.removeLast();
    writeJson(paths.notificationsFile,
        notifications.map((e) => e.toJson()).toList());
    toasts.add(n);
    Timer(Duration(seconds: settings.toastSec.clamp(1, 60)), () {
      toasts.remove(n);
      _changed();
    });
    _changed();
  }

  void dismissToast(AppNotification n) {
    toasts.remove(n);
    _changed();
  }

  void clearNotifications() {
    notifications.clear();
    writeJson(paths.notificationsFile, const []);
    _changed();
  }

  void clearHistory() {
    history.clear();
    writeJson(paths.historyFile, const []);
    _changed();
  }

  void _log(String level, String message, [int line = 0]) {
    logs.add(LogEntry(DateTime.now(), level, message, line));
    if (logs.length > 5000) logs.removeRange(0, 1000);
    logVersion.value++;
  }

  void setLogHeight(double h) {
    settings.logHeight = h.round().clamp(80, 2000);
    _changed();
  }

  void toggleLog() {
    settings.logCollapsed = !settings.logCollapsed;
    saveSettings();
  }

  void clearLog() {
    logs.clear();
    logVersion.value++;
  }

  String logText() => logs.map((e) => e.format()).join('\n');
}
