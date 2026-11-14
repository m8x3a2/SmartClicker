// Settings of the program (settings.json), their groups and reset to defaults.

import 'dart:convert';

/// Settings by the blocks of the settings page (names in settings.json).
/// 'layout' is the look of the window; "reset all" resets it too. Not
/// reset at all: keys of single scripts, breakpoints, the OCR engine.
const settingsGroups = <String, List<String>>{
  'general': ['recPercent', 'showClicks', 'pickFromWindow'],
  'editor': ['hintTyping', 'hintHover'],
  'mini': ['miniKey', 'miniOnRun'],
  'tray': ['trayOnMinimize', 'trayOnClose'],
  'startup': ['autostartTray'],
  'data': ['resetWord'],
  'hotkeys': ['stopKey', 'stopKey2', 'cornerStop', 'pauseKey', 'recordKey', 'pickKey', 'runKey', 'holdBackHotkeys'],
  'run': [
    'runDelaySec', 'maxRuntimeMin', 'maxLoops', 'checkBeforeRun', //
    'restartOnError', 'restartDelaySec', 'allowPower',
  ],
  'record': [
    'recordDelaySec', 'recMode', 'recDwellMs', 'recWindow', 'recText', //
    'recSystemKeys', 'recSmart', 'recRequireWindow',
  ],
  'human': ['human', 'clickOffset', 'timeJitterPct', 'typeDelayMs'],
  'logs': ['saveLogs', 'saveReports', 'historySize', 'toastSec'],
  'layout': [
    'dryRun', 'logHeight', 'logCollapsed', 'helpCollapsed', 'bottomTab', //
    'editorView', 'blocksPalette', 'blocksSplitPct', 'miniX', 'miniY',
  ],
};

class Settings {
  String stopKey = 'f12';

  /// Second stop key: stops only a running script, not the recording
  /// (Esc is often a part of what is recorded).
  String stopKey2 = 'esc';

  /// The user moves the mouse into a corner of the screen: the running
  /// script stops (off by default: a script may go there on its own).
  bool cornerStop = false;

  /// "F12 / ESC" for hints about stopping a running script.
  String get stopKeysLabel => [stopKey, stopKey2]
      .where((k) => k.isNotEmpty)
      .map((k) => k.toUpperCase())
      .join(' / ');
  String pauseKey = 'f8';
  String recordKey = 'f9';
  String pickKey = 'f6';
  String runKey = '';

  /// Hotkeys do not reach the active program (keyboard hook).
  bool holdBackHotkeys = true;

  /// Script name -> hotkey that starts it.
  Map<String, String> scriptKeys = {};
  int runDelaySec = 2;
  int recordDelaySec = 3;
  int maxRuntimeMin = 0;
  int maxLoops = 0;

  /// The script is checked for mistakes before a run from the editor.
  bool checkBeforeRun = true;

  /// After an error the script starts again, at most this many times in a
  /// row (0 — off), after a pause of [restartDelaySec].
  int restartOnError = 0;
  int restartDelaySec = 10;
  bool recPercent = true;
  bool recSmart = true;
  bool human = false;
  int clickOffset = 0;

  /// Pause between the letters of type("…"), ms (programs lose letters
  /// sent all at once).
  int typeDelayMs = 50;
  int timeJitterPct = 0;
  int toastSec = 5;
  int historySize = 100;
  bool dryRun = false;
  bool saveLogs = true;
  int logHeight = 200;
  bool logCollapsed = false;

  /// Help: the list of sections is folded into a strip of icons.
  bool helpCollapsed = false;

  /// A script error saves a report (log, script, screenshot) in reports.
  bool saveReports = true;
  bool recText = true;
  String recMode = 'clicks';
  int recDwellMs = 500;
  bool recWindow = false;
  bool recSystemKeys = true;

  /// «Взять координаты кликом» counts from the window under the cursor and
  /// copies `with_window("…") { click(…) }` instead of screen coordinates.
  bool pickFromWindow = false;

  /// Recording bound to windows also writes require_window("…").
  bool recRequireWindow = true;
  bool showClicks = false;

  /// Scripts may shut down, restart, put to sleep or log off the computer.
  bool allowPower = false;

  /// Mini panel: hotkey, last position (physical px), auto-collapse on run.
  String miniKey = '';
  int? miniX, miniY;
  bool miniOnRun = false;

  /// System tray: minimizing hides the window to the tray; the close
  /// button hides it there too instead of quitting.
  bool trayOnMinimize = true;

  /// Started together with Windows: go to the tray right away.
  bool autostartTray = true;

  /// The word to type before "reset everything" (up to 30 letters).
  String resetWord = 'reset';
  bool trayOnClose = false;
  bool hintTyping = true;
  bool hintHover = true;

  /// Breakpoints: script name -> line numbers.
  Map<String, List<int>> breakpoints = {};

  /// Under the editor: 'log' or 'vars' (values of variables).
  String bottomTab = 'log';

  /// How a script is edited: 'code', 'blocks' or 'split' (both side by
  /// side); the palette of blocks is open; share of the blocks in 'split', %.
  String editorView = 'code';
  bool blocksPalette = true;
  int blocksSplitPct = 55;

  /// Text recognition of scripts: 'windows' (fast) or 'paddle' (accurate).
  String ocrEngine = 'paddle';

  /// The user picked the engine themselves. Settings saved before PaddleOCR
  /// became the default switch to it once.
  bool ocrChosen = false;

  Settings();

  /// The values of [keys] (names in settings.json) are the defaults.
  bool isDefault(Iterable<String> keys) {
    final d = Settings().toJson(), c = toJson();
    return keys.every((k) => jsonEncode(d[k]) == jsonEncode(c[k]));
  }

  /// A copy with the values of [keys] back to the defaults.
  Settings withDefaults(Iterable<String> keys) {
    final d = Settings().toJson(), c = toJson();
    for (final k in keys) {
      c[k] = d[k];
    }
    return Settings.fromJson(c);
  }

  factory Settings.fromJson(Object? json) {
    final s = Settings();
    if (json is! Map) return s;
    T get<T>(String k, T def) => json[k] is T ? json[k] as T : def;
    s.stopKey = get('stopKey', s.stopKey);
    s.stopKey2 = get('stopKey2', s.stopKey2);
    s.cornerStop = get('cornerStop', s.cornerStop);
    s.pauseKey = get('pauseKey', s.pauseKey);
    s.recordKey = get('recordKey', s.recordKey);
    s.pickKey = get('pickKey', s.pickKey);
    s.runKey = get('runKey', s.runKey);
    s.holdBackHotkeys = get('holdBackHotkeys', s.holdBackHotkeys);
    final sk = json['scriptKeys'];
    if (sk is Map) {
      s.scriptKeys = {for (final e in sk.entries) '${e.key}': '${e.value}'};
    }
    s.runDelaySec = get('runDelaySec', s.runDelaySec);
    s.recordDelaySec = get('recordDelaySec', s.recordDelaySec);
    s.maxRuntimeMin = get('maxRuntimeMin', s.maxRuntimeMin);
    s.maxLoops = get('maxLoops', s.maxLoops);
    s.checkBeforeRun = get('checkBeforeRun', s.checkBeforeRun);
    s.restartOnError = get('restartOnError', s.restartOnError);
    s.restartDelaySec = get('restartDelaySec', s.restartDelaySec);
    s.recPercent = get('recPercent', s.recPercent);
    s.recSmart = get('recSmart', s.recSmart);
    s.human = get('human', s.human);
    s.clickOffset = get('clickOffset', s.clickOffset);
    s.typeDelayMs = get('typeDelayMs', s.typeDelayMs);
    s.timeJitterPct = get('timeJitterPct', s.timeJitterPct);
    s.toastSec = get('toastSec', s.toastSec);
    s.historySize = get('historySize', s.historySize);
    s.dryRun = get('dryRun', s.dryRun);
    s.saveLogs = get('saveLogs', s.saveLogs);
    s.logHeight = get('logHeight', s.logHeight);
    s.logCollapsed = get('logCollapsed', s.logCollapsed);
    s.helpCollapsed = get('helpCollapsed', s.helpCollapsed);
    s.saveReports = get('saveReports', s.saveReports);
    s.recText = get('recText', s.recText);
    s.recMode = get('recMode', s.recMode);
    s.recDwellMs = get('recDwellMs', s.recDwellMs);
    s.recWindow = get('recWindow', s.recWindow);
    s.recSystemKeys = get('recSystemKeys', s.recSystemKeys);
    s.pickFromWindow = get('pickFromWindow', s.pickFromWindow);
    s.recRequireWindow = get('recRequireWindow', s.recRequireWindow);
    s.showClicks = get('showClicks', s.showClicks);
    s.allowPower = get('allowPower', s.allowPower);
    s.miniKey = get('miniKey', s.miniKey);
    s.miniX = get<int?>('miniX', null);
    s.miniY = get<int?>('miniY', null);
    s.miniOnRun = get('miniOnRun', s.miniOnRun);
    s.trayOnMinimize = get('trayOnMinimize', s.trayOnMinimize);
    s.autostartTray = get('autostartTray', s.autostartTray);
    final w = get('resetWord', s.resetWord).trim();
    s.resetWord = w.isEmpty || w.length > 30 ? 'reset' : w;
    s.trayOnClose = get('trayOnClose', s.trayOnClose);
    s.hintTyping = get('hintTyping', s.hintTyping);
    s.hintHover = get('hintHover', s.hintHover);
    final bp = json['breakpoints'];
    if (bp is Map) {
      s.breakpoints = {
        for (final e in bp.entries)
          if (e.value is List) '${e.key}': (e.value as List).whereType<int>().toList()
      };
    }
    s.bottomTab = get('bottomTab', s.bottomTab);
    s.editorView = get('editorView', s.editorView);
    if (!const {'code', 'blocks', 'split'}.contains(s.editorView)) s.editorView = 'code';
    s.blocksPalette = get('blocksPalette', s.blocksPalette);
    s.blocksSplitPct = get('blocksSplitPct', s.blocksSplitPct).clamp(15, 85);
    s.ocrChosen = get('ocrChosen', false);
    if (s.ocrChosen) s.ocrEngine = get('ocrEngine', s.ocrEngine);
    return s;
  }

  Map<String, Object?> toJson() => {
        'stopKey': stopKey,
        'stopKey2': stopKey2,
        'cornerStop': cornerStop,
        'pauseKey': pauseKey,
        'recordKey': recordKey,
        'pickKey': pickKey,
        'runKey': runKey,
        'holdBackHotkeys': holdBackHotkeys,
        'scriptKeys': scriptKeys,
        'runDelaySec': runDelaySec,
        'recordDelaySec': recordDelaySec,
        'maxRuntimeMin': maxRuntimeMin,
        'maxLoops': maxLoops,
        'checkBeforeRun': checkBeforeRun,
        'restartOnError': restartOnError,
        'restartDelaySec': restartDelaySec,
        'recPercent': recPercent,
        'recSmart': recSmart,
        'human': human,
        'clickOffset': clickOffset,
        'typeDelayMs': typeDelayMs,
        'timeJitterPct': timeJitterPct,
        'toastSec': toastSec,
        'historySize': historySize,
        'dryRun': dryRun,
        'saveLogs': saveLogs,
        'logHeight': logHeight,
        'logCollapsed': logCollapsed,
        'helpCollapsed': helpCollapsed,
        'saveReports': saveReports,
        'recText': recText,
        'recMode': recMode,
        'recDwellMs': recDwellMs,
        'recWindow': recWindow,
        'recSystemKeys': recSystemKeys,
        'pickFromWindow': pickFromWindow,
        'recRequireWindow': recRequireWindow,
        'showClicks': showClicks,
        'allowPower': allowPower,
        'miniKey': miniKey,
        'miniX': miniX,
        'miniY': miniY,
        'miniOnRun': miniOnRun,
        'trayOnMinimize': trayOnMinimize,
        'autostartTray': autostartTray,
        'resetWord': resetWord,
        'trayOnClose': trayOnClose,
        'hintTyping': hintTyping,
        'hintHover': hintHover,
        'breakpoints': breakpoints,
        'bottomTab': bottomTab,
        'editorView': editorView,
        'blocksPalette': blocksPalette,
        'blocksSplitPct': blocksSplitPct,
        'ocrEngine': ocrEngine,
        'ocrChosen': ocrChosen,
      };
}
