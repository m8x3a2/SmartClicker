// Checks the real system counters (no power actions):
//   dart run tool/smoke_system.dart [process]
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:smart_clicker/platform/windows/windows_backend.dart';

void main(List<String> args) {
  final b = WindowsBackend();
  final name = args.isEmpty ? 'explorer' : args.first;
  final s1 = b.cpuTimes()!;
  final p1 = b.processCpuTimes(name);
  final sw = Stopwatch()..start();
  var x = 0;
  while (sw.elapsedMilliseconds < 700) {
    x++; // keep one core busy
  }
  sleep(const Duration(milliseconds: 300));
  final s2 = b.cpuTimes()!;
  final p2 = b.processCpuTimes(name);
  final total = s2.total - s1.total;
  print('loop $x; cpus ${Platform.numberOfProcessors}; '
      'system total ${(total / 1e7).toStringAsFixed(2)} s CPU over 1 s wall');
  print('system busy ${((total - (s2.idle - s1.idle)) * 100 / total).toStringAsFixed(1)}%');
  final used = [for (final e in p2.entries) e.value - (p1[e.key] ?? e.value)]
      .fold(0, (a, b) => a + b);
  print('$name: ${p2.length} processes, ${(used * 100 / total).toStringAsFixed(1)}%');
  final m = b.memoryStatus()!;
  print('RAM total ${m.total >> 20} MB, free ${m.free >> 20} MB');
  print('$name memory ${(b.processMemory(name) ?? -1) >> 20} MB; '
      'nope -> ${b.processMemory('no_such_process')}');
  print('own process memory ${(b.processMemory('dart') ?? -1) >> 20} MB');
}
