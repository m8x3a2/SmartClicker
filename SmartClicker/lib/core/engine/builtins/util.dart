// Built-in functions: log, notify, run_script, options, random, conversions.
part of '../runtime.dart';

extension ScriptRuntimeBuiltinsUtil on ScriptRuntime {
  void _registerUtil() {
    _def('log', (c) {
      log(c.args.map(stringify).join(' '));
      return null;
    }, ['print']);
    _def('warn', (c) {
      log(c.args.map(stringify).join(' '), 'warn');
      return null;
    });
    _def('notify', (c) {
      emit({
        't': 'notify',
        'title': stringify(c.arg(0)),
        'body': c.args.length > 1 ? stringify(c.arg(1)) : '',
      });
      return null;
    });
    _def('exit', (c) => throw const ExitSignal(), ['stop']);

    // The questions are asked by the app before the run (one window for
    // all of them); here the answers are only looked up.
    final answers = Map<String, Object?>.from((cfg['answers'] as Map?) ?? const {});
    final unasked = <String>{};
    _def('ask', (c) {
      final prompt = _s(c, c.arg(0, 'text'), 'ask');
      final spec = askSpec(prompt, c.arg(1, 'default'), c.arg(2, 'options'), line: c.line);
      if (answers.containsKey(prompt)) return spec.pick(answers[prompt]);
      if (unasked.add(prompt)) {
        log('ask("$prompt"): вопрос не задавался перед запуском (текст вопроса или '
            'значение по умолчанию вычисляются во время работы) — взято ${stringify(spec.def, quote: true)}', 'warn');
      }
      return spec.def;
    });

    _def('run_script', (c) async {
      final name = _s(c, c.arg(0), 'run_script');
      final src = _scriptSource(name);
      if (src == null) c.fail('run_script: скрипт "$name" не найден');
      if (_nested >= 20) c.fail('run_script: слишком глубокая вложенность скриптов');
      log('▶ скрипт "$name"');
      final program = parseProgram(src, script: name);
      _nested++;
      try {
        await interp.run(program);
      } on ScriptError catch (e) {
        e.script ??= name;
        rethrow;
      } finally {
        _nested--;
      }
      return null;
    });

    _def('set_option', (c) {
      final name = _s(c, c.arg(0), 'set_option');
      final v = c.arg(1);
      switch (name) {
        case 'human':
          humanMode = truthy(v);
        case 'click_offset' || 'offset':
          clickOffset = _n(c, v, name);
        case 'time_jitter' || 'jitter':
          timeJitter = v is Percent ? v.value / 100 : _n(c, v, name).toDouble();
          if (timeJitter > 1) timeJitter /= 100;
        case 'dry_run':
          dryRun = truthy(v);
        case 'type_delay':
          typeDelay = _n(c, v, name);
        default:
          c.fail('set_option: неизвестная настройка "$name" '
              '(human, click_offset, time_jitter, type_delay, dry_run)');
      }
      return null;
    });

    _def('random', (c) {
      if (c.args.isEmpty) return rng.nextDouble();
      if (c.args.length == 1) return rng.nextDouble() * _n(c, c.arg(0), 'random');
      final a = _n(c, c.arg(0), 'random'), b = _n(c, c.arg(1), 'random');
      return a + rng.nextDouble() * (b - a);
    });
    _def('random_int', (c) {
      final a = _n(c, c.arg(0), 'random_int').round();
      final b = _n(c, c.arg(1), 'random_int').round();
      final lo = math.min(a, b), hi = math.max(a, b);
      return lo + rng.nextInt(hi - lo + 1);
    });
    _def('chance', (c) {
      final v = c.arg(0);
      final p = v is Percent ? v.value / 100 : _n(c, v, 'chance');
      return rng.nextDouble() < (p > 1 ? p / 100 : p);
    });
    _def('pick', (c) {
      final list = c.arg(0);
      if (list is! List || list.isEmpty) return null;
      return list[rng.nextInt(list.length)];
    });

    _def('str', (c) => stringify(c.arg(0)), ['String']);
    _def('int', (c) {
      final v = c.arg(0);
      if (v is String) return num.tryParse(v.trim())?.truncate();
      return _n(c, v, 'int').truncate();
    }, ['parseInt']);
    _def('float', (c) {
      final v = c.arg(0);
      if (v is String) return num.tryParse(v.trim())?.toDouble();
      return _n(c, v, 'float').toDouble();
    }, ['num', 'Number', 'parseFloat']);
    _def('len', (c) {
      final v = c.arg(0);
      if (v is String) return v.length;
      if (v is List) return v.length;
      if (v is Map) return v.length;
      c.fail('len: нужна строка, массив или объект');
    });
    _def('type_of', (c) => typeName(c.arg(0)), ['typeof']);
    _def('keys', (c) {
      final v = c.arg(0);
      return v is Map ? v.keys.toList().cast<Object?>() : <Object?>[];
    });
    _def('to_json', (c) => jsonEncode(_jsonSafe(c.arg(0))));
    _def('from_json', (c) {
      try {
        return jsonDecode(_s(c, c.arg(0), 'from_json'));
      } on FormatException catch (e) {
        c.fail('from_json: некорректный JSON: ${e.message}');
      }
    });

    num n1(CallCtx c) => _n(c, c.arg(0), 'число');
    final mathFns = <String, BuiltinFn>{
      'abs': (c) => n1(c).abs(),
      'floor': (c) => n1(c).floor(),
      'ceil': (c) => n1(c).ceil(),
      'round': (c) => n1(c).round(),
      'sqrt': (c) => math.sqrt(n1(c)),
      'pow': (c) => math.pow(n1(c), _n(c, c.arg(1), 'pow')),
      'min': (c) => c.args.map((a) => _n(c, a, 'min')).reduce(math.min),
      'max': (c) => c.args.map((a) => _n(c, a, 'max')).reduce(math.max),
      'random': (c) => rng.nextDouble(),
    };
    final mathObj = <String, Object?>{'PI': math.pi};
    mathFns.forEach((name, fn) {
      final b = Builtin(name, fn);
      mathObj[name] = b;
      if (name != 'random') interp.define(name, b);
    });
    interp.define('Math', mathObj);

    final logFn = interp.globals.get('log');
    interp.define('console', <String, Object?>{
      'log': logFn,
      'info': logFn,
      'warn': interp.globals.get('warn'),
      'error': interp.globals.get('warn'),
    });
    interp.define('JSON', <String, Object?>{
      'stringify': interp.globals.get('to_json'),
      'parse': interp.globals.get('from_json'),
    });
  }
}
