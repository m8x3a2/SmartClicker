// Built-in functions: windows and programs (focus, use_window, launch...).
part of '../runtime.dart';

extension ScriptRuntimeBuiltinsWindows on ScriptRuntime {
  /// "30 с", "1.5 с" for messages.
  static String _secs(num ms) => '${fmtNum((ms / 100).round() / 10)} с';

  void _registerWindows() {
    _def('active_window', (c) => backend.activeWindow()?.toMap());
    _def('windows', (c) => backend.windows().map((w) => w.toMap()).toList());
    _def('window_exists', (c) => _findWindow(_s(c, c.arg(0), 'window_exists')) != null);
    _def('is_window_active', (c) =>
        backend.activeWindow()?.matches(_s(c, c.arg(0), 'is_window_active')) ?? false);

    _def('focus_window', (c) async {
      final q = _s(c, c.arg(0), 'focus_window');
      final w = _findWindow(q);
      if (w == null) {
        log('focus_window: окно "$q" не найдено', 'warn');
        return false;
      }
      if (dryRun) {
        log('[тест] активировать окно "${w.title}"', 'action');
        return true;
      }
      log('активировать окно "${w.title}"', 'action');
      final ok = backend.focusWindow(w.handle);
      await this.sleep(150, jitter: false);
      return ok;
    });

    _def('set_window_bounds', (c) {
      final q = _s(c, c.arg(0), 'set_window_bounds');
      final w = _findWindow(q);
      if (w == null) {
        log('set_window_bounds: окно "$q" не найдено', 'warn');
        return false;
      }
      final x = _n(c, c.arg(1), 'x').round(), y = _n(c, c.arg(2), 'y').round();
      final ww = _n(c, c.arg(3), 'w').round(), hh = _n(c, c.arg(4), 'h').round();
      if (dryRun) {
        log('[тест] окно "${w.title}" → $x,$y ${ww}x$hh', 'action');
        return true;
      }
      log('окно "${w.title}" → $x,$y ${ww}x$hh', 'action');
      return backend.setWindowBounds(w.handle, x, y, ww, hh);
    });

    _def('use_window', (c) {
      final q = c.arg(0);
      if (q == null || q == false) {
        _originWindow = null;
        return true;
      }
      final w = _findWindow(_s(c, q, 'use_window'));
      if (w == null) c.fail('use_window: окно "$q" не найдено');
      _originWindow = w.handle;
      log('Координаты теперь считаются от окна "${w.title}"');
      return true;
    });
    _def('use_screen', (c) {
      _originWindow = null;
      return true;
    });

    _def('require_window', (c) {
      final q = c.arg(0);
      _requiredWindow = (q == null || q == false) ? null : _s(c, q, 'require_window');
      _requireFocus = truthy(c.opt('focus', true));
      _requiredHandle = null;
      return null;
    });

    // use_window + require_window(focus: true) for the block after the call
    // only: `with_window("Game") { click(50%, 50%) }`. Waits up to
    // timeout: (30 s) for the window to appear; restore: true — the window
    // that was active before the block comes back to the front after it.
    _def('with_window', (c) async {
      final q = _s(c, c.arg(0), 'with_window');
      var w = _findWindow(q);
      if (w == null) {
        final timeout = _nOr(c, c.opt('timeout'), 30000, 'timeout');
        if (timeout > 0) {
          log('with_window: окна "$q" нет — жду до ${_secs(timeout)}…', 'warn');
          _emitLine();
          final sw = Stopwatch()..start();
          while (w == null && sw.elapsedMilliseconds < timeout) {
            await this.sleep(500, jitter: false);
            w = _findWindow(q);
          }
        }
        if (w == null) {
          c.fail('with_window: окно "$q" не найдено'
              '${timeout > 0 ? ' и не появилось за ${_secs(timeout)}' : ''}');
        }
      }
      final before = truthy(c.opt('restore', false)) ? backend.activeWindow() : null;
      final saved = (_originWindow, _requiredWindow, _requireFocus, _requiredHandle);
      _originWindow = w.handle;
      _requiredWindow = q;
      _requireFocus = truthy(c.opt('focus', true));
      _requiredHandle = w.handle;
      log('Блок в окне "${w.title}": координаты от окна, нажатия — только в него');
      return ScopeExit(() async {
        _originWindow = saved.$1;
        _requiredWindow = saved.$2;
        _requireFocus = saved.$3;
        _requiredHandle = saved.$4;
        final back = before;
        if (back == null || backend.activeWindow()?.handle == back.handle) return;
        if (dryRun) {
          log('[тест] вернуть вперёд окно "${back.title}"', 'action');
          return;
        }
        log('Возвращаю вперёд окно "${back.title}"', 'action');
        backend.focusWindow(back.handle);
        await this.sleep(100, jitter: false);
      });
    });

    _def('is_process_running', (c) {
      final q = _s(c, c.arg(0), 'is_process_running').toLowerCase();
      return backend.processes().any((p) {
        final n = p.toLowerCase();
        return n == q || n == '$q.exe';
      });
    });

    _def('kill_process', (c) {
      final q = _s(c, c.arg(0), 'kill_process');
      if (dryRun) {
        log('[тест] завершить процесс $q', 'action');
        return 0;
      }
      log('завершить процесс $q', 'action');
      return backend.killProcess(q);
    });

    _def('run_command', (c) async {
      final cmd = _s(c, c.arg(0), 'run_command');
      if (dryRun) {
        log('[тест] команда: $cmd', 'action');
        return null;
      }
      log('команда: $cmd', 'action');
      final exe = Platform.isWindows ? 'cmd' : 'sh';
      final args = Platform.isWindows ? ['/c', cmd] : ['-c', cmd];
      if (c.opt('wait', true) == false) {
        await Process.start(exe, args, mode: ProcessStartMode.detached);
        return null;
      }
      final r = await Process.run(exe, args);
      return <String, Object?>{
        'code': r.exitCode,
        'out': '${r.stdout}'.trim(),
        'err': '${r.stderr}'.trim(),
      };
    });

    _def('launch', (c) async {
      final path = _s(c, c.arg(0), 'launch');
      final base = path.replaceAll(r'\', '/').split('/').last.toLowerCase();
      final isProgram = !path.contains('://') &&
          (base.endsWith('.exe') || !base.contains('.'));
      if (isProgram && !truthy(c.opt('new', false))) {
        final running = backend.processes().any((p) {
          final n = p.toLowerCase();
          return n == base || n == '$base.exe';
        });
        if (running) {
          log('$base уже запущен — второй экземпляр не открываю '
              '(нужен ещё один: launch("...", new: true))');
          return false;
        }
      }
      if (dryRun) {
        log('[тест] запустить $path', 'action');
        return true;
      }
      log('запустить $path', 'action');
      if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', '', path],
            mode: ProcessStartMode.detached);
      } else {
        await Process.start('sh', ['-c', path], mode: ProcessStartMode.detached);
      }
      return true;
    });
  }
}
