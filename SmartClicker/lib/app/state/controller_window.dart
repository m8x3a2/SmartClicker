// The program window: tray, mini panel and the "Access" screen.
part of 'app_controller.dart';

extension AppControllerWindow on AppController {
  /// What the program can and cannot do on this computer right now.
  AccessFacts accessFacts() {
    final elevated = backend.isElevated();
    final admin = <String>{};
    if (Platform.isWindows && !elevated) {
      final own = pid;
      final seen = <int>{};
      for (final w in backend.windows()) {
        if (w.pid == own || w.title.trim().isEmpty || !seen.add(w.pid)) continue;
        if (w.process.isEmpty || AppController._systemProcesses.contains(w.process.toLowerCase())) {
          continue;
        }
        if (backend.isProcessElevated(w.pid) != false) admin.add(w.process);
      }
    }
    return AccessFacts(
      windows: Platform.isWindows,
      elevated: elevated,
      adminApps: admin.toList()..sort(),
      paddle: PaddleOcr.installed(paths.ocr),
      winOcrLanguages: backend.ocrLanguages(),
      allowPower: settings.allowPower,
      dataDir: paths.base,
      startsWithWindows: startupInfo().active,
    );
  }

  /// A button of the "Access" screen.
  void accessAction(String action) {
    switch (action) {
      case 'admin':
        if (backend.restartElevated()) {
          quit();
        } else {
          notify('Не перезапущено', 'Windows не дал прав администратора (запрос отменён)',
              level: 'warn');
        }
      case 'ocr':
        openPage('vision');
      case 'power':
        settings.allowPower = !settings.allowPower;
        saveSettings();
      case 'data':
        openFolder(paths.base);
      case 'startup':
        setStartWithWindows(!startupInfo().active);
    }
  }

  String _trayTip() {
    final name = _runScript ?? '';
    return switch (state) {
      RunState.running => 'SmartClicker — работает «$name»',
      RunState.paused => 'SmartClicker — пауза «$name»',
      RunState.recording || RunState.recCountdown => 'SmartClicker — запись',
      RunState.countdown => 'SmartClicker — сейчас запустится',
      _ => 'SmartClicker',
    };
  }

  /// The dot on the tray icon: green — running, yellow — paused or about
  /// to start (also before a restart after an error), red — the last run
  /// stopped with an error and the window was not opened since.
  static String trayMarkFor(RunState state, {required bool error}) => switch (state) {
    RunState.running => 'run',
    RunState.paused || RunState.countdown => 'pause',
    _ => error ? 'error' : '',
  };

  /// Shows, updates or removes the tray icon to match the settings.
  void _syncTray() {
    final want = settings.trayOnMinimize || settings.trayOnClose || hiddenToTray;
    if (!want) {
      if (_trayShown) backend.hideTray();
      _trayShown = false;
      _trayTipShown = '';
      return;
    }
    // The red dot goes once the user has looked at the window.
    if (trayError && !hiddenToTray && _ownWindowActive()) trayError = false;
    final tip = trayError && state == RunState.idle ? '${_trayTip()} — ошибка в «${_runScript ?? ''}»' : _trayTip();
    final mark = AppControllerWindow.trayMarkFor(state, error: trayError);
    if (_trayShown && tip == _trayTipShown && mark == _trayMarkShown) return;
    _trayShown = backend.showTray(tip, _onTrayEvent, mark: mark);
    _trayTipShown = _trayShown ? tip : '';
    _trayMarkShown = _trayShown ? mark : '';
  }

  /// Hides the window; the tray icon stays. Does nothing without a tray
  /// (the window would be lost).
  void hideToTray() {
    if (hiddenToTray || compact) return;
    hiddenToTray = true;
    _syncTray();
    if (!_trayShown) {
      hiddenToTray = false;
      return;
    }
    backend.hideMainWindow();
    if (!_trayHintShown) {
      _trayHintShown = true;
      backend.trayBalloon('SmartClicker в трее',
          'Горячие клавиши работают. Открыть — щелчок по значку, меню — правой кнопкой');
    }
    _changed();
  }

  void restoreFromTray() {
    if (!hiddenToTray) {
      backend.activateSelf();
      return;
    }
    hiddenToTray = false;
    backend.showMainWindow();
    _syncTray();
    _changed();
  }

  void _onTrayEvent(String event) {
    if (event == 'open') restoreFromTray();
    if (event == 'menu') _showTrayMenu();
  }

  void _showTrayMenu() {
    final m = AppController.trayMenuFor(state, current, _runScript, stopKey: settings.stopKey);
    final i = backend.trayMenu(m.items, bold: 0);
    if (i < 0 || i >= m.actions.length) return;
    switch (m.actions[i]) {
      case 'open':
        restoreFromTray();
      case 'run':
        if (state == RunState.idle && current != null) runByName(current!, via: 'tray');
      case 'pause':
        togglePause();
      case 'stop':
        stop();
      case 'quit':
        quit();
    }
  }

  /// Quits for real (the "Exit" item): unsaved scripts are still asked
  /// about.
  Future<void> quit() async {
    quitting = true;
    restoreFromTray();
    final r = await ServicesBinding.instance.exitApplication(AppExitType.cancelable);
    if (r == AppExitResponse.cancel) quitting = false;
  }

  void setCompact(bool on, {bool auto = false, bool activate = true}) {
    if (on == compact) return;
    if (on) {
      final views = WidgetsBinding.instance.platformDispatcher.views;
      final scale = views.isEmpty ? 1.0 : views.first.devicePixelRatio;
      if (!backend.enterPanel(settings.miniX, settings.miniY,
          (AppController.miniWidth * scale).round(), (AppController.miniHeight * scale).round())) {
        notify('Мини-панель недоступна',
            'На этой системе окно нельзя свернуть в панель',
            level: 'warn');
        return;
      }
      // The hidden editor must not keep receiving keystrokes.
      FocusManager.instance.primaryFocus?.unfocus();
      _autoCompact = auto;
    } else {
      rememberPanelPos();
      backend.leavePanel(activate: activate);
      _autoCompact = false;
    }
    compact = on;
    _changed();
    // The window changes its size asynchronously; once (2026-11-19) the
    // panel kept showing the old big frame squeezed into it. One more frame
    // after the resize has surely arrived.
    Future.delayed(const Duration(milliseconds: 250), () {
      if (compact != on) return;
      _changed();
      WidgetsBinding.instance.scheduleForcedFrame();
    });
  }

  void toggleCompact() => setCompact(!compact);

  void rememberPanelPos() {
    final b = backend.panelBounds();
    if (b == null) return;
    settings.miniX = b.x;
    settings.miniY = b.y;
    saveSettingsQuiet();
  }

  /// Start button of the mini panel. The panel does not take the focus, so
  /// the right window is usually active already and no countdown is needed.
  void runFromPanel() {
    if (busy || current == null) return;
    if (_ownWindowActive()) {
      run(via: 'mini');
    } else {
      runByName(current!, via: 'mini');
    }
  }
}
