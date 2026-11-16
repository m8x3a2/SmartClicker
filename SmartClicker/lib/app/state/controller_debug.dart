// Debugging: breakpoints (they move with their lines) and values of variables.
part of 'app_controller.dart';

extension AppControllerDebug on AppController {
  void toggleBreakpoint(int line) {
    if (current == null) return;
    final set = {...breaks.value};
    if (!set.remove(line)) set.add(line);
    _setBreaks(set);
  }

  void clearBreakpoints() => _setBreaks(const {});

  void _setBreaks(Set<int> set) {
    breaks.value = set;
    if (set.isEmpty) {
      settings.breakpoints.remove(current);
    } else {
      settings.breakpoints[current!] = set.toList()..sort();
    }
    saveSettingsQuiet();
    if (isRunning && _runScript == current) _runner.setBreakpoints(set);
  }

  /// Variables of the open script shown on the mini panel.
  List<String> get pinned => settings.pinnedVars[current] ?? const [];

  /// Shows a variable of the open script on the mini panel, or stops showing it.
  void togglePinned(String name) {
    final script = current;
    if (script == null) return;
    final list = [...pinned];
    if (!list.remove(name)) list.add(name);
    if (list.isEmpty) {
      settings.pinnedVars.remove(script);
    } else {
      settings.pinnedVars[script] = list;
    }
    saveSettingsQuiet();
    if (isRunning && _runScript == script) {
      _runner.setPinned(list);
      if (!list.contains(name)) shown.value = {...shown.value}..remove(name);
    }
    _changed();
  }

  /// Lines were added or removed while editing: breakpoints below the
  /// cursor move with their lines; the ones on removed lines go away.
  void _shiftBreaks(int delta) {
    final sel = editor.selection.baseOffset.clamp(0, editor.text.length);
    final cursor = '\n'.allMatches(editor.text.substring(0, sel)).length + 1;
    _setBreaks(AppController.shiftLines(breaks.value, delta, cursor));
  }

  void setBottomTab(String tab) {
    if (settings.bottomTab == tab) return;
    settings.bottomTab = tab;
    saveSettingsQuiet();
    if (isRunning) _runner.setWatch(tab == 'vars' || settings.stateFile);
    _changed();
  }

  void _onVars(List rows) {
    final next = rows.whereType<Map>().map(VarRow.of).toList();
    final old = {for (final r in vars.value) '${r.scope}|${r.name}': r.value};
    changedVars
      ..clear()
      ..addAll(next
          .where((r) => old.isNotEmpty && old['${r.scope}|${r.name}'] != r.value)
          .map((r) => '${r.scope}|${r.name}'));
    vars.value = next;
  }
}
