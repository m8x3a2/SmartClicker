// Interpreter of ClickScript: walks the syntax tree; every step is async so a
// script can be paused and stopped anywhere.

import 'dart:math' as math;

import 'ast.dart';
import 'values.dart';

/// Callbacks the interpreter needs from its embedder.
abstract class Host {
  /// Called before every statement; may pause, yield or throw [StopSignal].
  Future<void> checkpoint(int line);

  /// Called once per loop iteration (for the global loop limiter).
  void loopTick(int line);
}

class Env {
  final Map<String, Object?> vars = {};
  final Env? parent;
  Env(this.parent);

  Env? _find(String name) {
    for (Env? e = this; e != null; e = e.parent) {
      if (e.vars.containsKey(name)) return e;
    }
    return null;
  }

  bool has(String name) => _find(name) != null;
  Object? get(String name) => _find(name)?.vars[name];
  void define(String name, Object? v) => vars[name] = v;
}

class UserFn {
  final FuncE def;
  final Env closure;
  const UserFn(this.def, this.closure);
  @override
  String toString() => '<функция ${def.name ?? ''}>';
}

class Interpreter {
  final Host host;
  final Env globals = Env(null);
  final math.Random rng;
  int _depth = 0;

  /// Scope of the statement being run (for the variables view).
  Env? currentEnv;

  /// Names of the user functions being run, innermost last.
  final List<String> frames = [];

  Interpreter(this.host, {math.Random? random}) : rng = random ?? math.Random();

  void define(String name, Object? value) => globals.define(name, value);

  /// Runs a program in the global scope (so its functions stay available).
  Future<void> run(List<Stmt> program) async {
    try {
      // Hoist function declarations so they can be called before definition.
      for (final s in program) {
        if (s is FuncDecl) globals.define(s.fn.name!, UserFn(s.fn, globals));
      }
      for (final s in program) {
        await exec(s, globals);
      }
    } on ReturnSignal {
      // `return` at top level simply ends the script.
    } on BreakSignal {
      throw ScriptError('break вне цикла', 0);
    } on ContinueSignal {
      throw ScriptError('continue вне цикла', 0);
    }
  }

  // --------------------------------------------------------------- statements

  Future<void> execBlock(List<Stmt> body, Env env) async {
    for (final s in body) {
      if (s is FuncDecl) env.define(s.fn.name!, UserFn(s.fn, env));
    }
    for (final s in body) {
      await exec(s, env);
    }
  }

  Future<void> exec(Stmt s, Env env) async {
    currentEnv = env;
    await host.checkpoint(s.line);
    switch (s) {
      case ExprS():
        await eval(s.e, env);
      case VarS():
        for (final d in s.decls) {
          env.define(d.key, d.value == null ? null : await eval(d.value!, env));
        }
      case Block():
        await execBlock(s.body, Env(env));
      case If():
        if (truthy(await eval(s.cond, env))) {
          await exec(s.then, env);
        } else if (s.otherwise != null) {
          await exec(s.otherwise!, env);
        }
      case While():
        if (s.doWhile) {
          do {
            if (!await _iteration(s.body, env, s.line)) break;
          } while (truthy(await eval(s.cond, env)));
        } else {
          while (truthy(await eval(s.cond, env))) {
            if (!await _iteration(s.body, env, s.line)) break;
          }
        }
      case ForC():
        final scope = Env(env);
        if (s.init != null) await exec(s.init!, scope);
        while (s.cond == null || truthy(await eval(s.cond!, scope))) {
          if (!await _iteration(s.body, scope, s.line)) break;
          if (s.step != null) await eval(s.step!, scope);
        }
      case ForIn():
        final it = await eval(s.iterable, env);
        final Iterable<Object?> items;
        if (it is List) {
          items = List.of(it);
        } else if (it is Map) {
          items = List.of(it.keys);
        } else if (it is String) {
          items = it.split('');
        } else if (it is RangeVal) {
          final lo = it.lo.round(), hi = it.hi.round();
          items = lo <= hi
              ? Iterable.generate(hi - lo + 1, (i) => lo + i)
              : Iterable.generate(lo - hi + 1, (i) => lo - i);
        } else if (it is num) {
          items = Iterable.generate(it.round(), (i) => i);
        } else {
          throw ScriptError(
              'По значению типа ${typeName(it)} нельзя пройти циклом', s.line);
        }
        for (final item in items) {
          final scope = Env(env)..define(s.name, item);
          if (!await _iteration(s.body, scope, s.line)) break;
        }
      case Repeat():
        if (s.count == null) {
          while (true) {
            if (!await _iteration(s.body, env, s.line)) break;
          }
        } else {
          final n = _num(await eval(s.count!, env), s.line).round();
          for (var i = 0; i < n; i++) {
            if (!await _iteration(s.body, env, s.line)) break;
          }
        }
      case WithS():
        final scope = await eval(s.call, env);
        try {
          await exec(s.body, env);
        } finally {
          if (scope is ScopeExit) await scope.restore();
        }
      case Break():
        throw const BreakSignal();
      case Continue():
        throw const ContinueSignal();
      case Return():
        throw ReturnSignal(s.value == null ? null : await eval(s.value!, env));
      case FuncDecl():
        env.define(s.fn.name!, UserFn(s.fn, env));
      case Switch():
        final v = await eval(s.subject, env);
        var start = -1;
        for (var i = 0; i < s.cases.length; i++) {
          final test = s.cases[i].test;
          if (test != null && _eq(v, await eval(test, env))) {
            start = i;
            break;
          }
        }
        if (start < 0) start = s.cases.indexWhere((c) => c.test == null);
        if (start >= 0) {
          final scope = Env(env);
          try {
            for (var i = start; i < s.cases.length; i++) {
              for (final st in s.cases[i].body) {
                await exec(st, scope);
              }
            }
          } on BreakSignal {
            // end of switch
          }
        }
      case Try():
        try {
          await exec(s.body, env);
        } on ScriptError catch (e) {
          if (s.handler == null) rethrow;
          await _handle(s, env, e.message);
        } on ThrowSignal catch (e) {
          if (s.handler == null) rethrow;
          await _handle(s, env, e.value);
        } finally {
          if (s.finalizer != null) await exec(s.finalizer!, env);
        }
      case Throw():
        throw ThrowSignal(await eval(s.value, env), s.line);
    }
  }

  Future<void> _handle(Try s, Env env, Object? error) async {
    final scope = Env(env);
    if (s.errName != null) scope.define(s.errName!, error);
    await execBlock(s.handler!.body, scope);
  }

  /// Runs one loop iteration; returns false when the loop should stop.
  Future<bool> _iteration(Stmt body, Env env, int line) async {
    host.loopTick(line);
    try {
      await exec(body, env);
    } on BreakSignal {
      return false;
    } on ContinueSignal {
      // next iteration
    }
    return true;
  }

  // -------------------------------------------------------------- expressions

  num _num(Object? v, int line) {
    if (v is num) return v;
    if (v is RangeVal) {
      if (v.lo is int && v.hi is int) {
        final lo = math.min(v.lo, v.hi) as int, hi = math.max(v.lo, v.hi) as int;
        return lo + rng.nextInt(hi - lo + 1);
      }
      return v.lo + rng.nextDouble() * (v.hi - v.lo);
    }
    throw ScriptError(
        'Ожидалось число, а получено ${typeName(v)} (${stringify(v)})', line);
  }

  bool _eq(Object? a, Object? b) {
    if (a is num && b is num) return a == b;
    if (a is Percent && b is Percent) return a.value == b.value;
    return a == b;
  }

  Future<Object?> eval(Expr e, Env env) async {
    switch (e) {
      case Lit():
        return e.value;
      case TemplateE():
        final sb = StringBuffer();
        for (final part in e.parts) {
          sb.write(part is Expr ? stringify(await eval(part, env)) : part);
        }
        return sb.toString();
      case Ident():
        final scope = env._find(e.name);
        if (scope == null) {
          throw ScriptError("Неизвестное имя '${e.name}'", e.line);
        }
        return scope.vars[e.name];
      case ArrayE():
        final out = <Object?>[];
        for (final it in e.items) {
          out.add(await eval(it, env));
        }
        return out;
      case MapE():
        final out = <String, Object?>{};
        for (final en in e.entries) {
          out[en.key] = await eval(en.value, env);
        }
        return out;
      case Unary():
        final v = await eval(e.e, env);
        if (e.op == '!') return !truthy(v);
        if (v is Percent) return Percent(e.op == '-' ? -v.value : v.value);
        final n = _num(v, e.line);
        return e.op == '-' ? -n : n;
      case Binary():
        return _binary(
            e.op, await eval(e.l, env), await eval(e.r, env), e.line);
      case Logical():
        final l = await eval(e.l, env);
        if (e.op == '&&') return truthy(l) ? await eval(e.r, env) : l;
        if (e.op == '??') return l ?? await eval(e.r, env);
        return truthy(l) ? l : await eval(e.r, env);
      case Ternary():
        return truthy(await eval(e.c, env))
            ? await eval(e.a, env)
            : await eval(e.b, env);
      case RangeE():
        final lo = await eval(e.lo, env), hi = await eval(e.hi, env);
        if (lo is! num || hi is! num) {
          throw ScriptError('Диапазон a..b задаётся числами', e.line);
        }
        return RangeVal(lo, hi);
      case Assign():
        var v = await eval(e.value, env);
        if (e.op != '=') {
          final old = await eval(e.target, env);
          v = _binary(e.op.substring(0, e.op.length - 1), old, v, e.line);
        }
        await _assign(e.target, v, env);
        return v;
      case Update():
        final old = _num(await eval(e.target, env), e.line);
        final nv = e.op == '++' ? old + 1 : old - 1;
        await _assign(e.target, nv, env);
        return e.prefix ? nv : old;
      case FuncE():
        return UserFn(e, env);
      case Member():
        return _member(await eval(e.obj, env), e.name, e.line);
      case Index():
        final obj = await eval(e.obj, env);
        final idx = await eval(e.idx, env);
        if (obj is List) {
          final i = _num(idx, e.line).toInt();
          final j = i < 0 ? obj.length + i : i;
          return j >= 0 && j < obj.length ? obj[j] : null;
        }
        if (obj is String) {
          final i = _num(idx, e.line).toInt();
          return i >= 0 && i < obj.length ? obj[i] : null;
        }
        if (obj is Map) return obj[stringify(idx)];
        throw ScriptError(
            'Нельзя взять [${stringify(idx)}] у значения типа ${typeName(obj)}',
            e.line);
      case Call():
        return _call(e, env);
    }
  }

  Future<void> _assign(Expr target, Object? v, Env env) async {
    switch (target) {
      case Ident():
        // Assigning to an undeclared name creates a global (forgiving mode).
        (env._find(target.name) ?? globals).vars[target.name] = v;
      case Member():
        final obj = await eval(target.obj, env);
        if (obj is! Map) {
          throw ScriptError('Свойство можно задать только объекту', target.line);
        }
        obj[target.name] = v;
      case Index():
        final obj = await eval(target.obj, env);
        final idx = await eval(target.idx, env);
        if (obj is List) {
          final i = _num(idx, target.line).toInt();
          if (i < 0) throw ScriptError('Отрицательный индекс', target.line);
          while (obj.length <= i) {
            obj.add(null);
          }
          obj[i] = v;
        } else if (obj is Map) {
          obj[stringify(idx)] = v;
        } else {
          throw ScriptError('Сюда нельзя присвоить по индексу', target.line);
        }
      default:
        throw ScriptError('Сюда нельзя присвоить значение', target.line);
    }
  }

  Object? _binary(String op, Object? a, Object? b, int line) {
    switch (op) {
      case '==' || '===':
        return _eq(a, b);
      case '!=' || '!==':
        return !_eq(a, b);
      case '+':
        if (a is num && b is num) return a + b;
        if (a is String || b is String) return stringify(a) + stringify(b);
        if (a is Percent && b is Percent) return Percent(a.value + b.value);
        if (a is List && b is List) return [...a, ...b];
      case '-':
        if (a is num && b is num) return a - b;
        if (a is Percent && b is Percent) return Percent(a.value - b.value);
      case '*':
        if (a is num && b is num) return a * b;
        if (a is Percent && b is num) return Percent(a.value * b);
        if (a is num && b is Percent) return Percent(a * b.value);
      case '/':
        if (a is num && b is num) {
          if (b == 0) throw ScriptError('Деление на ноль', line);
          if (a is int && b is int && a % b == 0) return a ~/ b;
          return a / b;
        }
        if (a is Percent && b is num && b != 0) return Percent(a.value / b);
      case '%':
        if (a is num && b is num) {
          if (b == 0) throw ScriptError('Деление на ноль', line);
          return a.remainder(b);
        }
      case '<' || '<=' || '>' || '>=':
        int? c;
        if (a is num && b is num) c = a.compareTo(b);
        if (a is String && b is String) c = a.compareTo(b);
        if (a is Percent && b is Percent) c = a.value.compareTo(b.value);
        if (c != null) {
          return switch (op) {
            '<' => c < 0,
            '<=' => c <= 0,
            '>' => c > 0,
            _ => c >= 0,
          };
        }
    }
    throw ScriptError(
        "Операция '$op' не подходит для ${typeName(a)} и ${typeName(b)}", line);
  }

  Object? _member(Object? obj, String name, int line) {
    if (obj is Map) return obj[name];
    if (name == 'length') {
      if (obj is String) return obj.length;
      if (obj is List) return obj.length;
    }
    if (obj is Percent && name == 'value') return obj.value;
    if (obj is RangeVal) {
      if (name == 'lo' || name == 'min') return obj.lo;
      if (name == 'hi' || name == 'max') return obj.hi;
    }
    if (obj == null) {
      throw ScriptError("Нельзя прочитать '.$name' у null", line);
    }
    throw ScriptError(
        "У значения типа ${typeName(obj)} нет свойства '$name'", line);
  }

  Future<Object?> _call(Call e, Env env) async {
    final args = <Object?>[];
    final callee = e.callee;
    Object? fn;
    Object? receiver;
    String? method;
    if (callee is Member) {
      receiver = await eval(callee.obj, env);
      if (receiver is Map && receiver[callee.name] != null) {
        fn = receiver[callee.name];
      } else {
        method = callee.name;
      }
    } else if (callee is Ident) {
      final scope = env._find(callee.name);
      if (scope == null) {
        throw ScriptError("Неизвестная функция '${callee.name}'", e.line);
      }
      fn = scope.vars[callee.name];
    } else {
      fn = await eval(callee, env);
    }
    for (final a in e.args) {
      args.add(await eval(a, env));
    }
    var named = const <String, Object?>{};
    if (e.named.isNotEmpty) {
      named = {};
      for (final en in e.named.entries) {
        named[en.key] = await eval(en.value, env);
      }
    }
    if (method != null) return _method(receiver, method, args, e.line);
    return callFunction(fn, args, named, e.line);
  }

  Future<Object?> callFunction(Object? fn, List<Object?> args,
      Map<String, Object?> named, int line) async {
    if (fn is Builtin) {
      try {
        return await fn.fn(CallCtx(args, named, line));
      } on ScriptError {
        rethrow;
      } on ArgumentError catch (e) {
        throw ScriptError('${fn.name}: ${e.message}', line);
      } on FormatException catch (e) {
        throw ScriptError('${fn.name}: ${e.message}', line);
      } on StateError catch (e) {
        throw ScriptError('${fn.name}: ${e.message}', line);
      }
    }
    if (fn is UserFn) {
      if (_depth > 150) {
        throw ScriptError('Слишком глубокая рекурсия', line);
      }
      final scope = Env(fn.closure);
      final ps = fn.def.params;
      for (var i = 0; i < ps.length; i++) {
        scope.define(
            ps[i], i < args.length ? args[i] : named[ps[i]]);
      }
      _depth++;
      frames.add(fn.def.name ?? 'функция');
      try {
        if (fn.def.exprBody != null) return await eval(fn.def.exprBody!, scope);
        await execBlock(fn.def.body!.body, scope);
      } on ReturnSignal catch (r) {
        return r.value;
      } finally {
        _depth--;
        frames.removeLast();
      }
      return null;
    }
    throw ScriptError('Значение типа ${typeName(fn)} нельзя вызвать', line);
  }

  Future<Object?> _method(
      Object? o, String name, List<Object?> a, int line) async {
    Never bad() => throw ScriptError(
        "У значения типа ${typeName(o)} нет метода '$name'", line);
    Object? a0() => a.isNotEmpty ? a[0] : null;
    Future<Object?> cb(Object? item, int i) =>
        callFunction(a0(), [item, i], const {}, line);

    if (name == 'toString') return stringify(o);
    if (o is String) {
      switch (name) {
        case 'toUpperCase' || 'upper':
          return o.toUpperCase();
        case 'toLowerCase' || 'lower':
          return o.toLowerCase();
        case 'trim':
          return o.trim();
        case 'includes' || 'contains':
          return o.contains(stringify(a0()));
        case 'startsWith':
          return o.startsWith(stringify(a0()));
        case 'endsWith':
          return o.endsWith(stringify(a0()));
        case 'indexOf':
          return o.indexOf(stringify(a0()));
        case 'split':
          return o.split(a.isEmpty ? '' : stringify(a0())).cast<Object?>();
        case 'replace' || 'replaceAll':
          return o.replaceAll(stringify(a0()), stringify(a.length > 1 ? a[1] : ''));
        case 'substring' || 'slice':
          var st = a.isEmpty ? 0 : _num(a[0], line).toInt();
          var en = a.length > 1 ? _num(a[1], line).toInt() : o.length;
          if (st < 0) st = o.length + st;
          if (en < 0) en = o.length + en;
          st = st.clamp(0, o.length);
          en = en.clamp(st, o.length);
          return o.substring(st, en);
        case 'charAt':
          final i = _num(a0(), line).toInt();
          return i >= 0 && i < o.length ? o[i] : '';
        case 'repeat':
          return o * _num(a0(), line).toInt();
      }
      bad();
    }
    if (o is List) {
      switch (name) {
        case 'push' || 'add':
          o.addAll(a);
          return o.length;
        case 'pop':
          return o.isEmpty ? null : o.removeLast();
        case 'shift':
          return o.isEmpty ? null : o.removeAt(0);
        case 'unshift':
          o.insertAll(0, a);
          return o.length;
        case 'includes' || 'contains':
          return o.any((x) => _eq(x, a0()));
        case 'indexOf':
          return o.indexWhere((x) => _eq(x, a0()));
        case 'join':
          return o.map(stringify).join(a.isEmpty ? ',' : stringify(a0()));
        case 'reverse':
          final r = o.reversed.toList();
          o
            ..clear()
            ..addAll(r);
          return o;
        case 'concat':
          return [...o, for (final x in a) ...(x is List ? x : [x])];
        case 'slice':
          var st = a.isEmpty ? 0 : _num(a[0], line).toInt();
          var en = a.length > 1 ? _num(a[1], line).toInt() : o.length;
          if (st < 0) st = o.length + st;
          if (en < 0) en = o.length + en;
          st = st.clamp(0, o.length);
          en = en.clamp(st, o.length);
          return o.sublist(st, en);
        case 'sort':
          o.sort((x, y) => x is num && y is num
              ? x.compareTo(y)
              : stringify(x).compareTo(stringify(y)));
          return o;
        case 'map':
          final out = <Object?>[];
          for (var i = 0; i < o.length; i++) {
            out.add(await cb(o[i], i));
          }
          return out;
        case 'filter':
          final out = <Object?>[];
          for (var i = 0; i < o.length; i++) {
            if (truthy(await cb(o[i], i))) out.add(o[i]);
          }
          return out;
        case 'forEach':
          for (var i = 0; i < o.length; i++) {
            await cb(o[i], i);
          }
          return null;
        case 'find':
          for (var i = 0; i < o.length; i++) {
            if (truthy(await cb(o[i], i))) return o[i];
          }
          return null;
        case 'some':
          for (var i = 0; i < o.length; i++) {
            if (truthy(await cb(o[i], i))) return true;
          }
          return false;
        case 'every':
          for (var i = 0; i < o.length; i++) {
            if (!truthy(await cb(o[i], i))) return false;
          }
          return true;
      }
      bad();
    }
    if (o is Map) {
      switch (name) {
        case 'keys':
          return o.keys.toList().cast<Object?>();
        case 'values':
          return o.values.toList();
        case 'has' || 'hasOwnProperty':
          return o.containsKey(stringify(a0()));
        case 'remove' || 'delete':
          return o.remove(stringify(a0()));
      }
      bad();
    }
    if (o is num) {
      if (name == 'toFixed') {
        return o.toStringAsFixed(a.isEmpty ? 0 : _num(a0(), line).toInt());
      }
      bad();
    }
    if (o == null) {
      throw ScriptError("Нельзя вызвать '.$name()' у null", line);
    }
    bad();
  }
}
