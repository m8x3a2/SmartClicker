// Entry point: one copy of the program at a time, error journal, the app widget
// and the dialog about unsaved scripts on exit.

import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'app/state/app_controller.dart';
import 'core/reports/report.dart';
import 'core/storage/storage.dart';
import 'core/system/startup.dart';
import 'platform/windows/single_instance.dart';
import 'app/ui/editor/code_editor.dart';
import 'app/ui/home/home_screen.dart';

void main(List<String> args) {
  // One copy at a time: a second one shows the window of the first and
  // quits before its own window appears (it is shown after the first
  // frame). `--multi` skips the check (flutter run next to an open copy),
  // `--restarted` waits for the old copy (restart as administrator).
  if (Platform.isWindows && !args.contains('--multi')) {
    final waitMs = args.contains('--restarted') ? 60000 : 0;
    if (!SingleInstance.acquire(waitMs: waitMs)) {
      SingleInstance.activateOther();
      exit(0);
    }
  }
  WidgetsFlutterBinding.ensureInitialized();
  // Bugs of the program itself are written to logs/app_errors.log instead
  // of disappearing silently in the release build.
  ErrorJournal.path = AppPaths.detect().appErrorsFile;
  FlutterError.onError = (d) {
    FlutterError.presentError(d);
    ErrorJournal.record(d.exception, d.stack, where: d.library ?? 'flutter');
  };
  PlatformDispatcher.instance.onError = (e, s) {
    ErrorJournal.record(e, s);
    return true;
  };
  runApp(SmartClickerApp(startedWithWindows: args.contains(autostartArg)));
}

class SmartClickerApp extends StatefulWidget {
  /// Windows started the program at logon (see core/system/startup.dart).
  final bool startedWithWindows;
  const SmartClickerApp({super.key, this.startedWithWindows = false});

  @override
  State<SmartClickerApp> createState() => _SmartClickerAppState();
}

class _SmartClickerAppState extends State<SmartClickerApp> {
  late final AppController app = AppController(CodeController())
    ..startedWithWindows = widget.startedWithWindows;
  final _nav = GlobalKey<NavigatorState>();
  late final AppLifecycleListener _lifecycle =
      AppLifecycleListener(onExitRequested: _onExitRequested);

  @override
  void initState() {
    super.initState();
    _lifecycle; // start listening for the window being closed
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    app.dispose();
    super.dispose();
  }

  /// Closing the window with unsaved scripts asks what to do with them.
  Future<AppExitResponse> _onExitRequested() async {
    final r = await _askExit();
    // The tray icon would otherwise stay next to the clock until hovered.
    if (r == AppExitResponse.exit) {
      app.backend.hideTray();
      app.backend.stopKeyHook();
      app.backend.releaseAll(); // keys a running script holds
      // After a system file or folder dialog the shell keeps a hidden window
      // of its own thread in this process, and the normal shutdown of
      // Flutter then hangs: the window disappears, the process stays.
      // Everything is saved already, so the process ends right here.
      app.backend.endProcess();
    }
    return r;
  }

  Future<AppExitResponse> _askExit() async {
    // "Close to tray": the cross hides the window; "Exit" in the tray menu
    // quits for real.
    if (!app.quitting && app.settings.trayOnClose && !app.compact) {
      app.hideToTray();
      if (app.hiddenToTray) return AppExitResponse.cancel;
    }
    final ctx = _nav.currentContext;
    // A running script (it may be waiting for the night) is not cut off
    // without asking; if the program closes, the run is written as
    // interrupted.
    final running = app.runningScript;
    if (running != null && ctx != null) {
      app.setCompact(false);
      app.restoreFromTray();
      final go = await showDialog<bool>(
        context: ctx,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          title: const Text('Скрипт ещё работает'),
          content: Text('«$running» сейчас выполняется (может быть, ждёт нужного времени). '
              'Если закрыть программу, он остановится, а в истории запуск будет отмечен как '
              '«прерван: программа закрыта».'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Не закрывать')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Остановить и закрыть')),
          ],
        ),
      );
      if (go != true) return AppExitResponse.cancel;
    }
    app.interruptForExit();
    final unsaved = app.unsaved;
    final ctx2 = _nav.currentContext; // taken again: a window may have been shown above
    if (unsaved.isEmpty || ctx2 == null || !ctx2.mounted) return AppExitResponse.exit;
    app.setCompact(false); // the dialog needs the full window
    app.restoreFromTray();
    final choice = await showDialog<String>(
      context: ctx2,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('Есть несохранённые скрипты'),
        content: Text('Не сохранены:\n\n${unsaved.map((n) => '  •  $n').join('\n')}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, 'cancel'),
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(c, 'discard'),
              child: const Text('Не сохранять')),
          FilledButton(
              onPressed: () => Navigator.pop(c, 'save'),
              child: const Text('Сохранить всё')),
        ],
      ),
    );
    if (choice == 'save') app.saveAll();
    return choice == 'save' || choice == 'discard'
        ? AppExitResponse.exit
        : AppExitResponse.cancel;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartClicker',
      navigatorKey: _nav,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B82F6),
          brightness: Brightness.dark,
          surface: const Color(0xFF20232A),
        ),
        scaffoldBackgroundColor: const Color(0xFF20232A),
        fontFamily: 'Segoe UI',
      ),
      home: HomePage(app: app),
    );
  }
}
