// Values and signals of the language: percent, range, errors, break/return.

import 'dart:async';

/// A percentage literal such as `50%` (screen/window-relative coordinate).
class Percent {
  final double value;
  const Percent(this.value);
  @override
  String toString() => '${fmtNum(value)}%';
}

/// A range literal such as `1000..1500`; resolves to a random number when a
/// number is expected, and iterates integers in `for (i in a..b)`.
class RangeVal {
  final num lo;
  final num hi;
  const RangeVal(this.lo, this.hi);
  @override
  String toString() => '${fmtNum(lo)}..${fmtNum(hi)}';
}

class ScriptError implements Exception {
  final String message;
  final int line;
  String? script;
  ScriptError(this.message, this.line, [this.script]);
  @override
  String toString() =>
      '${script != null ? '[$script] ' : ''}Строка $line: $message';
}

class BreakSignal implements Exception {
  const BreakSignal();
}

class ContinueSignal implements Exception {
  const ContinueSignal();
}

class ReturnSignal implements Exception {
  final Object? value;
  const ReturnSignal(this.value);
}

/// Raised when the user (or kill-switch) stops the script.
class StopSignal implements Exception {
  const StopSignal();
}

/// Raised by `exit()` inside a script: a normal, successful end.
class ExitSignal implements Exception {
  const ExitSignal();
}

/// Raised when a safety limit (time / loop count) is hit.
class LimitSignal implements Exception {
  final String message;
  const LimitSignal(this.message);
}

/// A value thrown by the script's own `throw`.
class ThrowSignal implements Exception {
  final Object? value;
  final int line;
  const ThrowSignal(this.value, this.line);
}

/// Returned by a function whose effect lasts only for the block after it
/// (`with_window("Game") { ... }`): [restore] runs when the block ends,
/// however it ends.
class ScopeExit {
  final FutureOr<void> Function() restore;
  const ScopeExit(this.restore);
  @override
  String toString() => '<блок>';
}

class CallCtx {
  final List<Object?> args;
  final Map<String, Object?> named;
  final int line;
  const CallCtx(this.args, this.named, this.line);

  /// Positional argument [i], falling back to the named argument [name].
  Object? arg(int i, [String? name]) {
    if (i < args.length) return args[i];
    if (name != null) return named[name];
    return null;
  }

  Object? opt(String name, [Object? def]) =>
      named.containsKey(name) ? named[name] : def;

  Never fail(String message) => throw ScriptError(message, line);
}

typedef BuiltinFn = FutureOr<Object?> Function(CallCtx c);

class Builtin {
  final String name;
  final BuiltinFn fn;
  const Builtin(this.name, this.fn);
  @override
  String toString() => '<функция $name>';
}

String fmtNum(num n) {
  if (n is int) return '$n';
  if (n.isNaN || n.isInfinite) return '$n';
  if (n == n.roundToDouble() && n.abs() < 1e15) return n.toInt().toString();
  return double.parse(n.toStringAsFixed(6)).toString();
}

String stringify(Object? v, {bool quote = false}) {
  if (v == null) return 'null';
  if (v is num) return fmtNum(v);
  if (v is String) {
    return quote ? '"${v.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"' : v;
  }
  if (v is List) {
    return '[${v.map((e) => stringify(e, quote: true)).join(', ')}]';
  }
  if (v is Map) {
    return '{${v.entries.map((e) => '${e.key}: ${stringify(e.value, quote: true)}').join(', ')}}';
  }
  return v.toString();
}

bool truthy(Object? v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v.isNotEmpty;
  return true;
}

String typeName(Object? v) {
  if (v == null) return 'null';
  if (v is bool) return 'boolean';
  if (v is num) return 'number';
  if (v is String) return 'string';
  if (v is List) return 'array';
  if (v is Map) return 'object';
  if (v is Percent) return 'percent';
  if (v is RangeVal) return 'range';
  return 'function';
}
