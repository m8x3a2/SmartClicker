// Runs a script in its own isolate; messages between the isolate and the app.

import 'dart:async';
import 'dart:isolate';

import '../../platform/backend.dart';
import 'runtime.dart';

/// Entry point of the worker isolate. [init] = [SendPort, config map].
Future<void> _workerMain(List<Object?> init) async {
  final out = init[0] as SendPort;
  final cfg = Map<String, Object?>.from(init[1] as Map);
  final inbox = ReceivePort();
  final rt = ScriptRuntime(createBackend(), cfg, out.send);
  inbox.listen((m) {
    if (m == 'pause') rt.paused = true;
    if (m == 'resume') {
      rt.stepping = false;
      rt.paused = false;
    }
    if (m == 'step') {
      rt.stepping = true;
      rt.paused = false;
    }
    if (m == 'stop') {
      rt.stopRequested = true;
      rt.paused = false;
    }
    if (m case ['breaks', List lines]) {
      rt.breakpoints = lines.whereType<int>().toSet();
    }
    if (m case ['watch', bool on]) {
      rt.watch = on;
      if (on) rt.sendVariables(force: true);
    }
  });
  out.send({'t': 'ready', 'port': inbox.sendPort});
  final result = await rt.runMain();
  out.send(result);
  inbox.close();
}

/// Controls one script run from the UI isolate.
class ScriptRunner {
  final void Function(Map<String, Object?> event) onEvent;
  Isolate? _isolate;
  SendPort? _toWorker;
  ReceivePort? _fromWorker;
  Timer? _killTimer;
  bool _finished = false;
  final Stopwatch _sw = Stopwatch();

  ScriptRunner(this.onEvent);

  bool get running => _isolate != null && !_finished;

  Future<void> start(Map<String, Object?> cfg) async {
    _finished = false;
    _sw
      ..reset()
      ..start();
    final port = ReceivePort();
    _fromWorker = port;
    port.listen((m) {
      if (m is! Map) {
        // Uncaught error forwarded by the isolate: [error, stack].
        _finish({
          't': 'done',
          'status': 'error',
          'error': 'Сбой движка: ${m is List ? m.first : m}',
          'ms': _sw.elapsedMilliseconds,
        });
        return;
      }
      final e = Map<String, Object?>.from(m);
      if (e['t'] == 'ready') {
        _toWorker = e['port'] as SendPort;
      } else if (e['t'] == 'done') {
        _finish(e);
      } else {
        onEvent(e);
      }
    });
    _isolate = await Isolate.spawn(_workerMain, [port.sendPort, cfg],
        onError: port.sendPort, debugName: 'script');
  }

  void pause() => _toWorker?.send('pause');

  /// New breakpoints of the main script (line numbers).
  void setBreakpoints(Iterable<int> lines) =>
      _toWorker?.send(['breaks', lines.toList()]);

  /// Turns sending the values of variables on and off.
  void setWatch(bool on) => _toWorker?.send(['watch', on]);
  void resume() => _toWorker?.send('resume');

  /// Runs one more line and pauses again.
  void step() => _toWorker?.send('step');

  /// Asks the script to stop; kills the isolate if it does not obey quickly.
  void stop({Duration grace = const Duration(milliseconds: 400)}) {
    if (!running) return;
    _toWorker?.send('stop');
    _killTimer ??= Timer(grace, kill);
  }

  /// Hard kill: terminates the isolate immediately.
  void kill() {
    if (!running) return;
    _isolate?.kill(priority: Isolate.immediate);
    _finish({
      't': 'done',
      'status': 'killed',
      'ms': _sw.elapsedMilliseconds,
    });
  }

  void _finish(Map<String, Object?> e) {
    if (_finished) return;
    _finished = true;
    _killTimer?.cancel();
    _killTimer = null;
    _fromWorker?.close();
    _fromWorker = null;
    _isolate = null;
    _toWorker = null;
    onEvent(e);
  }
}
