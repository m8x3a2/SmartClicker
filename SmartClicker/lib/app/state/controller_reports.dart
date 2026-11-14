// Error reports: a ZIP with the script, log, variables and a screenshot.
part of 'app_controller.dart';

extension AppControllerReports on AppController {
  /// Writes a report ZIP into the reports folder and returns its path (the
  /// file appears a moment later: packing runs in the background).
  String? _saveReport(String name, String status, String? error,
      {String? other, bool shot = false}) {
    try {
      final now = DateTime.now();
      final path = '${paths.reports}${Platform.pathSeparator}'
          '${fileStamp(now)}_${ScriptStore.sanitize(name).replaceAll('/', '_')}.zip';
      Bitmap? screen;
      if (shot) {
        final s = backend.screenSize();
        if (s.w > 0 && s.h > 0) {
          screen = Bitmap(s.w, s.h, backend.capture(0, 0, s.w, s.h));
        }
      }
      final text = reportText(
        time: now,
        script: name,
        status: status,
        error: error,
        scripts: {
          name: name == _runScript ? _runSource : _sourceOf(name),
          if (other != null && other != name) other: _sourceOf(other),
        },
        log: logText(),
        variables: [for (final v in vars.value) '$v'],
        settings: settings.toJson()..remove('breakpoints'),
        environment: environment(),
        appErrors: ErrorJournal.tail(),
        screenshot: screen != null,
      );
      Directory(paths.reports).createSync(recursive: true);
      saveReport(path, text, screen).then(
          (_) => pruneFolder(paths.reports, 30),
          onError: (Object e, StackTrace s) =>
              ErrorJournal.record(e, s, where: 'report'));
      return path;
    } catch (e, s) {
      ErrorJournal.record(e, s, where: 'report');
      return null;
    }
  }

  String _sourceOf(String name) {
    if (name == current) return editor.text;
    return buffers[name] ?? (store.exists(name) ? store.read(name) : '');
  }

  /// What the report says about the computer and the program.
  Map<String, String> environment() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    final scale = views.isEmpty ? 1.0 : views.first.devicePixelRatio;
    final s = backend.screenSize();
    return {
      'Программа': 'SmartClicker $appVersion',
      'Система': Platform.operatingSystemVersion,
      'Экран': '${s.w}x${s.h}, масштаб ${(scale * 100).round()}%',
      'Распознавание текста': settings.ocrEngine,
      'Тестовый режим': settings.dryRun ? 'да' : 'нет',
    };
  }

  /// Saves a report by hand: for the last run (or for the open script if
  /// nothing ran yet), with a screenshot of the screen as it is now.
  String? saveReportNow() {
    final r = lastRun;
    final name = r?.script ?? current;
    if (name == null) return null;
    final path = _saveReport(name,
        r == null ? 'не запускался' : (statusLabels[r.status] ?? r.status),
        r?.error,
        shot: true);
    if (path != null) {
      notify('Отчёт сохранён', 'Сейчас откроется папка с ним', level: 'ok');
      Timer(const Duration(seconds: 2), () => showInFolder(path));
    }
    return path;
  }

  /// Opens Explorer with [path] selected.
  void showInFolder(String path) {
    if (Platform.isWindows) Process.start('explorer', ['/select,', path]);
  }

  void _onAppError(String message) {
    // Not more often than every 30 s, and never from inside a build.
    final now = DateTime.now();
    if (_lastAppError != null &&
        now.difference(_lastAppError!).inSeconds < 30) {
      return;
    }
    _lastAppError = now;
    Timer.run(() => notify(
        'Сбой в программе',
        'Записан в журнал logs/app_errors.log и попадёт в отчёт об ошибке. $message',
        level: 'error'));
  }
}
