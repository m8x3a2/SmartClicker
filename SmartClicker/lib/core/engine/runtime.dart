// ScriptRuntime: the environment of a running script (pause, stop, limits,
// breakpoints). Built-in functions are registered from builtins/.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../lang/ask_scan.dart';
import '../lang/interpreter.dart';
import '../lang/parser.dart';
import '../lang/script_refs.dart';
import '../lang/values.dart';
import '../../platform/backend.dart';
import '../../platform/keys.dart';
import 'human.dart';
import '../vision/image.dart';
import '../vision/paddle_ocr.dart';
import '../vision/ocr.dart';

part 'runtime_args.dart';
part 'runtime_input.dart';
part 'builtins/mouse.dart';
part 'builtins/keyboard.dart';
part 'builtins/time.dart';
part 'builtins/screen.dart';
part 'builtins/windows.dart';
part 'builtins/system.dart';
part 'builtins/util.dart';

typedef Emit = void Function(Map<String, Object?> event);

/// Runs one script: owns the interpreter, all built-in functions and the
/// safety logic (pause, stop, limits, releasing held keys).
class ScriptRuntime implements Host {
  final PlatformBackend backend;
  final Map<String, Object?> cfg;
  final Emit emit;
  final math.Random rng;
  late final Human human = Human(rng);
  late final Interpreter interp = Interpreter(this, random: rng);

  bool paused = false;
  bool stopRequested = false;

  /// Step-by-step mode: pause before every new line of the main script.
  late bool stepping = cfg['step'] == true;
  int _stepLine = -1;

  /// Lines of the main script to pause at.
  late Set<int> breakpoints = {
    ...((cfg['breaks'] as List?) ?? const []).whereType<int>()
  };

  /// Send the values of variables while running (the panel is open).
  late bool watch = cfg['watch'] == true;
  final Stopwatch _varsSw = Stopwatch()..start();
  String _sentVars = '';
  Set<String> _engineNames = const {};
  late final bool showClicks = cfg['showClicks'] == true;

  // Options (changeable from the script through set_option).
  late bool dryRun = cfg['dryRun'] == true;
  late bool humanMode = cfg['human'] == true;
  late num clickOffset = (cfg['clickOffset'] as num?) ?? 0;
  late num typeDelay = (cfg['typeDelay'] as num?) ?? 50; // ms between letters of type()
  late double timeJitter = ((cfg['timeJitter'] as num?) ?? 0).toDouble();
  late final int maxRuntimeMs = (cfg['maxRuntimeMs'] as num?)?.toInt() ?? 0;
  late final int maxLoops = (cfg['maxLoops'] as num?)?.toInt() ?? 0;

  final Stopwatch _total = Stopwatch();
  final Stopwatch _yield = Stopwatch();
  final Stopwatch _lineSw = Stopwatch();
  int _loops = 0;
  int _line = 0;
  int _sentLine = -1;
  int _nested = 0;

  final Set<String> _heldKeys = {};
  final Set<String> _heldButtons = {};
  String? _requiredWindow;
  bool _requireFocus = true; // require_window(focus:): bring it to front
  int? _requiredHandle; // the window require_window() last resolved to
  int? _originWindow; // handle set by use_window()
  final Stopwatch _sinceKeys = Stopwatch(); // since the last keyboard input
  int _keysUnsettled = 0; // keys sent since the last _settleKeys()
  Map<String, Object?>? _data;

  ScriptRuntime(this.backend, this.cfg, this.emit, {math.Random? random})
      : rng = random ?? math.Random() {
    _registerAll();
    _engineNames = interp.globals.vars.keys.toSet();
  }

  // ---------------------------------------------------------------- variables

  /// Short text of a value for the variables view.
  static String preview(Object? v, [int max = 200]) {
    String s;
    if (v is String) {
      s = stringify(v, quote: true);
    } else if (v is List && v.length > 30) {
      s = '[${v.take(30).map((e) => stringify(e, quote: true)).join(', ')}, … всего ${v.length}]';
    } else if (v is Map && v.length > 30) {
      s = '{${v.entries.take(30).map((e) => '${e.key}: ${stringify(e.value, quote: true)}').join(', ')}, … всего ${v.length}}';
    } else {
      s = stringify(v);
    }
    return s.length > max ? '${s.substring(0, max)}…' : s;
  }

  /// Variables visible at the current statement: the innermost scope
  /// first, then the script's global variables. Functions and the engine's
  /// own names are left out.
  List<Map<String, Object?>> variables() {
    final rows = <Map<String, Object?>>[];
    final seen = <String>{};
    final g = interp.globals;
    final frame = interp.frames.isEmpty ? null : interp.frames.last;
    for (Env? e = interp.currentEnv; e != null; e = e.parent) {
      final global = identical(e, g);
      for (final en in e.vars.entries) {
        final v = en.value;
        if (v is UserFn || v is Builtin) continue;
        if (global && _engineNames.contains(en.key)) continue;
        if (!seen.add(en.key)) continue; // hidden by an inner variable
        rows.add({
          'n': en.key,
          'v': preview(v),
          't': typeName(v),
          's': global ? '' : (frame ?? 'блок'),
        });
      }
    }
    return rows;
  }

  /// Sends the variables to the interface (only when they changed).
  void sendVariables({bool force = false}) {
    final rows = variables();
    final key = rows.map((r) => '${r['s']}|${r['n']}=${r['v']}').join('\n');
    if (!force && key == _sentVars) return;
    _sentVars = key;
    emit({'t': 'vars', 'rows': rows});
  }

  // ------------------------------------------------------------------ running

  /// Runs the main script and returns the final status event.
  Future<Map<String, Object?>> runMain() async {
    final name = cfg['main'] as String? ?? 'script';
    final source = (cfg['source'] as String?) ?? _scriptSource(name) ?? '';
    _total.start();
    _yield.start();
    _lineSw.start();
    String status = 'ok';
    String? error;
    int? line;
    String? script;
    try {
      final program = parseProgram(source, script: null);
      await interp.run(program);
    } on StopSignal {
      status = 'stopped';
    } on ExitSignal {
      status = 'ok';
    } on LimitSignal catch (e) {
      status = 'limit';
      error = e.message;
    } on ScriptError catch (e) {
      status = 'error';
      error = e.message;
      line = e.line;
      script = e.script;
    } on ThrowSignal catch (e) {
      status = 'error';
      error = 'Необработанное исключение: ${stringify(e.value)}';
      line = e.line;
    } catch (e, st) {
      status = 'error';
      error = 'Внутренняя ошибка: $e\n$st';
      line = _line;
    } finally {
      releaseAll();
    }
    // Values at the end (or at the moment of an error) for the variables
    // view and the error report.
    try {
      sendVariables(force: true);
    } catch (_) {}
    return {
      't': 'done',
      'status': status,
      'error': error,
      'line': line,
      'script': script,
      'ms': _total.elapsedMilliseconds,
      'loops': _loops,
    };
  }

  void releaseAll() {
    if (dryRun) return;
    for (final b in _heldButtons.toList()) {
      try {
        backend.mouseButton(b, false);
      } catch (_) {}
    }
    for (final k in _heldKeys.toList()) {
      try {
        backend.keyEvent(k, false);
      } catch (_) {}
    }
    _heldButtons.clear();
    _heldKeys.clear();
  }

  /// Finds a script by full path ("Папка/Имя") or just by its name.
  String? _scriptSource(String name) {
    final scripts = cfg['scripts'];
    if (scripts is! Map) return null;
    final found = resolveScriptName(name, scripts.keys.map((k) => '$k'));
    return found == null ? null : '${scripts[found]}';
  }

  void _checkLimits() {
    if (stopRequested) throw const StopSignal();
    if (maxRuntimeMs > 0 && _total.elapsedMilliseconds > maxRuntimeMs) {
      throw LimitSignal(
          'Сработал лимит времени: ${(maxRuntimeMs / 60000).toStringAsFixed(1)} мин');
    }
  }

  Future<void> _waitWhilePaused() async {
    while (paused) {
      if (stopRequested) throw const StopSignal();
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  }

  void _emitLine() {
    if (_nested == 0 && _line != _sentLine) {
      _sentLine = _line;
      emit({'t': 'line', 'l': _line});
      _lineSw.reset();
    }
  }

  @override
  Future<void> checkpoint(int line) async {
    _line = line;
    _checkLimits();
    if (_yield.elapsedMilliseconds >= 8) {
      // Let the isolate's event loop deliver pause/stop messages.
      await Future<void>.delayed(Duration.zero);
      _yield.reset();
      _checkLimits();
    }
    if ((stepping || breakpoints.contains(line)) &&
        _nested == 0 &&
        line != _stepLine) {
      _stepLine = line;
      paused = true;
      _sentLine = line;
      emit({'t': 'paused', 'l': line, 'why': stepping ? 'step' : 'break'});
      sendVariables(force: true);
    } else if (watch && _varsSw.elapsedMilliseconds >= 300) {
      _varsSw.reset();
      sendVariables();
    }
    if (paused) {
      _emitLine();
      await _waitWhilePaused();
    }
    if (_lineSw.elapsedMilliseconds >= 40) _emitLine();
  }

  @override
  void loopTick(int line) {
    _loops++;
    _stepLine = -1; // a loop body on one line still stops on every pass
    if (maxLoops > 0 && _loops > maxLoops) {
      throw LimitSignal('Сработал лимит циклов: $maxLoops повторений');
    }
  }

  /// Interruptible sleep; time spent on pause does not count.
  Future<void> sleep(num ms, {bool jitter = true}) async {
    if (jitter) ms = human.jitter(ms, timeJitter);
    var remaining = ms.round();
    if (remaining > 30) _emitLine();
    final sw = Stopwatch()..start();
    while (true) {
      _checkLimits();
      if (paused) {
        remaining -= sw.elapsedMilliseconds;
        _emitLine();
        await _waitWhilePaused();
        sw.reset();
        continue;
      }
      final left = remaining - sw.elapsedMilliseconds;
      if (left <= 0) break;
      await Future<void>.delayed(Duration(milliseconds: left > 25 ? 25 : left));
    }
    _yield.reset();
  }

  void log(String message, [String level = 'info']) =>
      emit({'t': 'log', 'lv': level, 'm': message, 'l': _line});

  bool _ocrFallbackLogged = false;

  /// Lower case, no repeated spaces: recognition is never letter-perfect.
  static String _loose(String s) => looseText(s);

  final Map<String, Bitmap> _images = {};

  static String hex(int rgb) =>
      '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';

  static int colorDiff(int a, int b) {
    final dr = ((a >> 16) & 0xFF) - ((b >> 16) & 0xFF);
    final dg = ((a >> 8) & 0xFF) - ((b >> 8) & 0xFF);
    final db = (a & 0xFF) - (b & 0xFF);
    return math.max(dr.abs(), math.max(dg.abs(), db.abs()));
  }

  // ---------------------------------------------------------------- builtins

  void _def(String name, BuiltinFn fn, [List<String> aliases = const []]) {
    final b = Builtin(name, fn);
    interp.define(name, b);
    // snake_case -> camelCase alias, so JS-style names work too.
    final camel = name.replaceAllMapped(
        RegExp(r'_([a-z])'), (m) => m.group(1)!.toUpperCase());
    if (camel != name) interp.define(camel, b);
    for (final a in aliases) {
      interp.define(a, b);
    }
  }

  void _registerAll() {
    _registerMouse();
    _registerKeyboard();
    _registerTime();
    _registerScreen();
    _registerWindows();
    _registerSystem();
    _registerUtil();
  }
}
