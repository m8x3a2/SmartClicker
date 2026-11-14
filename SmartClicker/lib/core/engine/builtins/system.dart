// Built-in functions: system and files (cpu, memory, power, clipboard, files, data).
part of '../runtime.dart';

extension ScriptRuntimeBuiltinsSystem on ScriptRuntime {
  void _registerSystem() {
    _def('battery_level', (c) => backend.batteryLevel());
    _def('is_charging', (c) => backend.isCharging());
    _def('is_network_connected', (c) => backend.networkConnected());

    // CPU load in percent over [interval] ms: the whole system, or the
    // processes with that name (share of all processors, as in Task Manager).
    _def('cpu_usage', (c) async {
      final q = c.arg(0);
      final name = q == null ? null : _s(c, q, 'cpu_usage');
      final interval = _nOr(c, c.opt('interval'), 500, 'interval');
      final s1 = backend.cpuTimes();
      final p1 = name == null ? null : backend.processCpuTimes(name);
      if (s1 == null) return null;
      if (p1 != null && p1.isEmpty) return null;
      await this.sleep(math.max(interval, 100), jitter: false);
      final s2 = backend.cpuTimes();
      if (s2 == null) return null;
      final total = s2.total - s1.total;
      if (total <= 0) return 0;
      double pct;
      if (name == null) {
        pct = (total - (s2.idle - s1.idle)) * 100 / total;
      } else {
        final p2 = backend.processCpuTimes(name);
        var used = 0;
        for (final e in p2.entries) {
          final before = p1![e.key];
          if (before != null) used += e.value - before;
        }
        if (p2.isEmpty) return null;
        pct = used * 100 / total;
      }
      return (pct.clamp(0, 100) * 10).round() / 10;
    });

    // Memory: the share of physical RAM in use, %, or the working set of
    // the processes with that name, MB.
    _def('ram_usage', (c) {
      final q = c.arg(0);
      if (q == null) {
        final m = backend.memoryStatus();
        if (m == null || m.total <= 0) return null;
        return ((m.total - m.free) * 1000 ~/ m.total) / 10;
      }
      final bytes = backend.processMemory(_s(c, q, 'ram_usage'));
      return bytes == null ? null : (bytes * 10 ~/ (1 << 20)) / 10;
    });
    _def('ram_info', (c) {
      final m = backend.memoryStatus();
      if (m == null) return null;
      int mb(int b) => b ~/ (1 << 20);
      return {
        'total': mb(m.total),
        'free': mb(m.free),
        'used': mb(m.total - m.free),
      };
    });

    _def('system_power', (c) {
      final action = _s(c, c.arg(0), 'system_power').toLowerCase().trim();
      const names = {
        'lock': 'заблокировать компьютер',
        'sleep': 'перевести компьютер в сон',
        'hibernate': 'перевести компьютер в гибернацию',
        'shutdown': 'выключить компьютер',
        'restart': 'перезагрузить компьютер',
        'logoff': 'выйти из учётной записи',
      };
      final what = names[action];
      if (what == null) {
        c.fail('system_power: неизвестное действие "$action". '
            'Можно: ${names.keys.map((k) => '"$k"').join(', ')}');
      }
      if (action != 'lock' && cfg['allowPower'] != true) {
        c.fail('system_power("$action"): скриптам запрещено $what. '
            'Разрешить: Настройки → Запуск → «Разрешить скриптам выключать компьютер»');
      }
      if (dryRun) {
        log('[тест] $what', 'action');
        return true;
      }
      log(what, 'action');
      releaseAll();
      final ok = backend.systemPower(action);
      if (!ok) log('system_power: Windows не выполнила «$what»', 'warn');
      return ok;
    });
    _def('get_clipboard', (c) => backend.getClipboard());
    _def('set_clipboard', (c) {
      backend.setClipboard(stringify(c.arg(0)));
      return null;
    });

    _def('read_file', (c) {
      final f = File(_path(_s(c, c.arg(0), 'read_file')));
      return f.existsSync() ? f.readAsStringSync() : null;
    });
    _def('write_file', (c) {
      File(_path(_s(c, c.arg(0), 'write_file'))).writeAsStringSync(stringify(c.arg(1)));
      return null;
    });
    _def('append_file', (c) {
      File(_path(_s(c, c.arg(0), 'append_file')))
          .writeAsStringSync(stringify(c.arg(1)), mode: FileMode.append);
      return null;
    });
    _def('file_exists', (c) => File(_path(_s(c, c.arg(0), 'file_exists'))).existsSync());

    _def('save_data', (c) {
      final d = _loadData();
      d[_s(c, c.arg(0), 'save_data')] = _jsonSafe(c.arg(1));
      try {
        _dataFile.writeAsStringSync(jsonEncode(d));
      } catch (e) {
        log('save_data: не удалось записать файл: $e', 'warn');
      }
      return null;
    });
    _def('load_data', (c) {
      final d = _loadData();
      final k = _s(c, c.arg(0), 'load_data');
      return d.containsKey(k) ? d[k] : c.arg(1, 'default');
    });
  }
}
