// State of the whole application: scripts, settings, runs, hotkeys, tray...
// The actions are split by topic into the parts controller_*.dart.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' show AppExitResponse, AppExitType;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/vision/image.dart';
import '../../core/vision/loupe.dart';
import '../../core/vision/picture_origin.dart';
import '../../core/vision/paddle_ocr.dart' show PaddleOcr;
import '../../core/engine/runner.dart';
import '../../core/engine/runtime.dart';
import '../../core/lang/ask_scan.dart';
import '../../core/lang/checker.dart';
import '../../core/lang/file_refs.dart';
import '../../core/lang/picture_refs.dart';
import '../../core/lang/script_refs.dart';
import '../../platform/backend.dart';
import '../../platform/keys.dart';
import '../../platform/stub_backend.dart';
import '../../core/system/access.dart';
import '../../core/system/startup.dart';
import '../../core/system/safety.dart';
import '../../core/automation/autorun.dart';
import '../../core/automation/file_watch.dart';
import '../../core/automation/game_guard.dart';
import '../../core/recorder/recorder.dart';
import '../../core/reports/report.dart';
import '../../core/storage/storage.dart';
import '../../core/storage/backup.dart';
import '../../core/storage/auto_backup.dart';
import '../../core/storage/clip_history.dart';
import '../../core/storage/trash.dart';
import '../../core/storage/script_versions.dart';
import '../../core/storage/share_pack.dart';
import '../../core/storage/zip.dart';
import 'click_map.dart';
import 'edit_history.dart';

export 'click_map.dart';

part 'controller_scripts.dart';
part 'controller_settings.dart';
part 'controller_debug.dart';
part 'controller_notify.dart';
part 'controller_run.dart';
part 'controller_autorun.dart';
part 'controller_window.dart';
part 'controller_files.dart';
part 'controller_reports.dart';
part 'controller_record.dart';
part 'controller_hotkeys.dart';
part 'controller_pick.dart';
part 'controller_landmarks.dart';
part 'controller_startup.dart';
part 'controller_corner.dart';
part 'controller_data.dart';
part 'controller_pictures.dart';
part 'controller_ask.dart';
part 'controller_batch.dart';
part 'controller_backup.dart';
part 'controller_safety.dart';
part 'controller_watch.dart';
part 'controller_requests.dart';
part 'controller_file_rules.dart';
part 'controller_guard.dart';
part 'controller_clipboard.dart';
part 'controller_trash.dart';

/// A piece of the screen selected by the user.
class ScreenCapture {
  final int x, y, w, h;
  final Bitmap image;
  const ScreenCapture(this.x, this.y, this.w, this.h, this.image);
}

enum RunState { idle, countdown, running, paused, recCountdown, recording }

class LogEntry {
  final DateTime time;
  final String level; // info, action, warn, error, system
  final String message;
  final int line;

  /// An error: the script it is in (the one that ran, or a connected one) —
  /// a click on the entry opens it on [line].
  final String? script;
  const LogEntry(this.time, this.level, this.message, this.line, {this.script});

  String get clock {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}.'
        '${time.millisecond.toString().padLeft(3, '0')}';
  }

  String format() =>
      '$clock [$level]${line > 0 && script == null ? ' (стр. $line)' : ''} $message';
}

class AppNotification {
  final DateTime time;
  final String title;
  final String body;
  final String level; // info, ok, warn, error
  const AppNotification(this.time, this.title, this.body, this.level);

  Map<String, Object?> toJson() => {
        'time': time.toIso8601String(),
        'title': title,
        'body': body,
        'level': level,
      };
  factory AppNotification.fromJson(Map j) => AppNotification(
      DateTime.tryParse('${j['time']}') ?? DateTime.now(),
      '${j['title']}',
      '${j['body']}',
      '${j['level']}');
}

class RunRecord {
  final String script;
  final DateTime started;
  final int durationMs;
  final String status;
  final String? error;
  final String? logFile;

  /// ZIP with the error report (log, scripts, screenshot), if one was made.
  final String? report;

  /// How it was started (see [runViaLabels]); '' — in older records.
  final String via;

  /// Ran in the test mode (actions only went to the log).
  final bool dry;

  /// The text of the script as it was at the start (null — not kept).
  final String? source;
  const RunRecord(this.script, this.started, this.durationMs, this.status,
      this.error, this.logFile,
      {this.report, this.via = '', this.dry = false, this.source});

  Map<String, Object?> toJson() => {
        'script': script,
        'started': started.toIso8601String(),
        'durationMs': durationMs,
        'status': status,
        'error': error,
        'logFile': logFile,
        'report': report,
        if (via.isNotEmpty) 'via': via,
        if (dry) 'dry': true,
        if (source != null) 'source': source,
      };
  factory RunRecord.fromJson(Map j) => RunRecord(
      '${j['script']}',
      DateTime.tryParse('${j['started']}') ?? DateTime.now(),
      (j['durationMs'] as num?)?.toInt() ?? 0,
      '${j['status']}',
      j['error'] as String?,
      j['logFile'] as String?,
      report: j['report'] as String?,
      via: '${j['via'] ?? ''}',
      dry: j['dry'] == true,
      source: j['source'] as String?);
}

/// The profile of a run: the slowest lines of the main script and the
/// slowest functions (see core/engine/runtime_profile.dart).
class RunProfile {
  final String script, source;
  final int totalMs;

  /// (line, µs, how many times it ran), slowest first.
  final List<(int, int, int)> lines;

  /// (function, calls, µs), slowest first.
  final List<(String, int, int)> calls;
  const RunProfile(this.script, this.source, this.totalMs, this.lines, this.calls);

  factory RunProfile.of(String script, String source, int totalMs, Map p) => RunProfile(
        script,
        source,
        totalMs,
        [
          for (final l in (p['lines'] as List? ?? const []))
            if (l is List && l.length == 3) ((l[0] as num).toInt(), (l[1] as num).toInt(), (l[2] as num).toInt())
        ],
        [
          for (final c in (p['calls'] as List? ?? const []))
            if (c is List && c.length == 3) ('${c[0]}', (c[1] as num).toInt(), (c[2] as num).toInt())
        ],
      );

  /// The text of line [n] of the script (1-based), trimmed.
  String lineText(int n) {
    final all = source.split('\n');
    return n >= 1 && n <= all.length ? all[n - 1].trim() : '';
  }
}

/// How a run was started: id → words for the history.
const runViaLabels = {
  'manual': 'вручную',
  'mini': 'с мини-панели',
  'tray': 'из трея',
  'key': 'клавишей',
  'schedule': 'по расписанию',
  'autorun': 'по программе',
  'file': 'по файлу',
  'external': 'извне (--run)',
  'restart': 'перезапуск после ошибки',
  'guard': 'сторож (после вылета программы)',
};

/// One variable in the variables view.
class VarRow {
  final String name, value, type;

  /// '' for a global variable, otherwise the function (or 'блок').
  final String scope;
  const VarRow(this.name, this.value, this.type, this.scope);

  factory VarRow.of(Map m) =>
      VarRow('${m['n']}', '${m['v']}', '${m['t']}', '${m['s'] ?? ''}');

  @override
  String toString() => '${scope.isEmpty ? '' : '[$scope] '}$name = $value';
}

class CursorInfo {
  final int x, y;
  final double px, py;
  final int color;
  const CursorInfo(this.x, this.y, this.px, this.py, this.color);
  String get hex => ScriptRuntime.hex(color);
}

/// How long a run took: "1 ч 05 мин", "3 мин 20 с", "4.2 с".
String formatDuration(int ms) {
  final s = ms ~/ 1000;
  if (s < 60) return '${(ms / 1000).toStringAsFixed(1)} с';
  if (s < 3600) return '${s ~/ 60} мин ${(s % 60).toString().padLeft(2, '0')} с';
  return '${s ~/ 3600} ч ${(s % 3600 ~/ 60).toString().padLeft(2, '0')} мин';
}

/// A short pause for hints: "200 мс", "0,5 с", "2 с".
String formatPause(int ms) => ms < 1000
    ? '$ms мс'
    : '${(ms / 1000).toStringAsFixed(ms % 1000 == 0 ? 0 : 1).replaceAll('.', ',')} с';

const statusLabels = {
  'ok': 'завершён',
  'stopped': 'остановлен',
  'killed': 'принудительно остановлен',
  'limit': 'остановлен по лимиту',
  'error': 'ошибка',
  'closed': 'прерван: программа закрыта',
  'guard': 'остановлен сторожем (программа вылетела или зависла)',
};

class AppController extends ChangeNotifier {
  final AppPaths paths = AppPaths.detect();
  final PlatformBackend backend = createBackend();
  late final ScriptStore store = ScriptStore(paths.scripts);
  Settings settings = Settings();

  // Scripts / editor
  List<String> scripts = [];
  List<String> folders = [];
  final Set<String> collapsed = {};
  String selectedFolder = '';
  String? current;
  final TextEditingController editor;
  bool dirty = false;
  bool _loading = false;
  String _savedText = '';

  /// The open script was changed on disk by another program while it has
  /// unsaved edits here: the text on disk (null — nothing to decide).
  String? externalText;

  /// Changes whenever another text is loaded into the editor, so the
  /// editor widget is rebuilt with an empty undo history (otherwise Ctrl+Z
  /// would bring back the text of the previously opened script).
  int editorEpoch = 0;

  /// Bumped by the menu command to open the search bar of the editor.
  final ValueNotifier<int> findRequest = ValueNotifier(0);

  /// Unsaved text of scripts that are not open right now.
  final Map<String, String> buffers = {};

  /// Undo / redo of every script opened in this session (Ctrl+Z, Ctrl+Y).
  final Map<String, EditHistory> _histories = {};
  bool _fromHistory = false;

  // Run state
  RunState state = RunState.idle;
  int countdown = 0;
  late final ScriptRunner _runner = ScriptRunner(_onEngineEvent);
  final List<LogEntry> logs = [];
  final ValueNotifier<int> logVersion = ValueNotifier(0);
  final ValueNotifier<int> currentLine = ValueNotifier(0);
  final ValueNotifier<int> errorLine = ValueNotifier(0);
  DateTime? _runStarted;
  String? _runScript;
  String _runSource = '';

  /// How the current run was started and whether in the test mode.
  String _runVia = 'manual';
  bool _runDry = false;

  /// The program is being closed: the run that ends now is "closed".
  bool _closing = false;

  /// Answers to the questions (ask) of the current run; a restart after an
  /// error reuses them.
  Map<String, Object?> _runAnswers = const {};

  /// Last answers of every script: script → {question: answer}.
  final Map<String, Object?> answers = {};

  /// Shows the window with the questions of a script (set by the interface).
  AskHandler? askHandler;

  /// After a rename: shows the run_script calls to fix, gives the chosen
  /// ones or null (set by the interface; without it everything is fixed).
  Future<List<RunScriptFix>?> Function(List<RunScriptFix> fixes)? runScriptFixHandler;

  /// The dry run of a folder in progress (see controller_batch.dart) and
  /// its summary when it is over (the interface shows it and clears it).
  ScriptRunner? _batch;
  bool _batchCancelled = false;
  final batchSummary = ValueNotifier<BatchSummary?>(null);

  /// The last finished run: a report can be saved for it by hand.
  RunRecord? lastRun;

  // Recorder / tools
  late Recorder _recorder;
  final ValueNotifier<int> recordMs = ValueNotifier(0);
  final ValueNotifier<CursorInfo?> cursor = ValueNotifier(null);
  bool trackCursor = false;

  // Notifications / history
  final List<AppNotification> notifications = [];
  final List<AppNotification> toasts = [];
  final List<RunRecord> history = [];
  final List<ScheduleTask> schedule = [];
  final DateTime _started = DateTime.now();

  Timer? _poll;
  int _tick = 0;
  final Map<String, bool> _hotkeyState = {};

  /// Presses of held-back combos counted by the hook (see quickPress).
  final Map<String, ({int gen, int count})> _hotkeyFired = {};
  bool _hotkeysSuspended = false;
  bool _holdBackWarned = false;

  /// A hotkey with Caps Lock fired: switch Caps Lock back once it is released.
  bool _capsRestore = false;

  /// "Mouse into a corner" stop: polls the mouse spent in a corner, the
  /// tick the check from the settings ends at, whether the mouse is watched.
  int _cornerTicks = 0;
  int _cornerTestUntil = 0;
  bool _mouseWatched = false;

  AppController(this.editor) {
    paths.ensure();
    ErrorJournal.path = paths.appErrorsFile;
    ErrorJournal.onRecord = _onAppError;
    final firstStart = !File(paths.settingsFile).existsSync();
    settings = Settings.fromJson(readJson(paths.settingsFile));
    store.versions = ScriptVersions(paths.versions, keep: settings.versionsKeep);
    final h = readJson(paths.historyFile);
    if (h is List) {
      history.addAll(h.whereType<Map>().map(RunRecord.fromJson));
    }
    final n = readJson(paths.notificationsFile);
    if (n is List) {
      notifications.addAll(n.whereType<Map>().map(AppNotification.fromJson));
    }
    if (firstStart && store.list().isEmpty) {
      exampleScripts
          .forEach((name, src) => store.write('$examplesFolder/$name', src));
    }
    final sch = readJson(paths.scheduleFile);
    if (sch is List) {
      schedule.addAll(sch.whereType<Map>().map(ScheduleTask.fromJson));
    }
    final ans = readJson(paths.answersFile);
    if (ans is Map) answers.addAll(Map<String, Object?>.from(ans));
    final auto = readJson(paths.autorunFile);
    if (auto is List) {
      autoRules.addAll(auto.whereType<Map>().map(AutoRule.fromJson));
    }
    final fr = readJson(paths.fileRulesFile);
    if (fr is List) {
      fileRules.addAll(fr.whereType<Map>().map(FileRule.fromJson));
    }
    final gr = readJson(paths.guardRulesFile);
    if (gr is List) {
      guardRules.addAll(gr.whereType<Map>().map(GuardRule.fromJson));
    }
    _refresh();
    editor.addListener(_onEdit);
    if (scripts.isNotEmpty) open(scripts.first);
    _recorder = _newRecorder();
    _poll = Timer.periodic(const Duration(milliseconds: 25), (_) => _onPoll());
    _warnUnreachableData();
  }

  @override
  void dispose() {
    _poll?.cancel();
    backend.hideTray();
    backend.stopKeyHook();
    if (_runner.running) _runner.kill();
    super.dispose();
  }

  bool get busy => state != RunState.idle;
  bool get isRunning => state == RunState.running || state == RunState.paused;

  int _lineCount = 1;
  String _editText = ""; // the editor text the last time it changed

  /// Breakpoints of the open script.
  final breaks = ValueNotifier<Set<int>>(const {});

  /// [delta] lines were added (or removed, if negative) and the cursor is
  /// now on [cursor]: line numbers below the edit move with their lines,
  /// the ones on removed lines go away.
  static Set<int> shiftLines(Set<int> lines, int delta, int cursor) {
    // The edit started on this line (numbering before the edit).
    final from = delta > 0 ? cursor - delta : cursor;
    return {
      for (final b in lines)
        if (b <= from)
          b
        else if (delta > 0 || b > from - delta)
          b + delta
    };
  }

  /// Values of the script's variables (the last ones sent by the engine).
  final vars = ValueNotifier<List<VarRow>>(const []);

  /// Names whose value changed in the last update (shown highlighted).
  final Set<String> changedVars = {};

  /// Changes whenever settings are reset: the fields of the settings page
  /// are created anew with the new values.
  int settingsEpoch = 0;

  bool _stepStart = false;
  bool _slowStart = false; // «Запустить замедленно»
  Timer? _markerTimer;

  /// Windows started the program at logon (`--autostart`): it goes to the
  /// tray as soon as its window appears, if the settings say so.
  bool startedWithWindows = false;

  /// Safe mode: nothing starts by itself (schedule, autorun, restart after
  /// an error); why it is on. See controller_safety.dart.
  bool safeMode = false;
  String safeReason = '';

  /// After a start with Windows automation waits until this moment.
  DateTime? automationHeldUntil;

  /// "Do not turn automation on until the program restarts".
  bool automationOff = false;
  SafetyJournal? _safety;

  /// Requests from other programs (--run / --stop) and when they came.
  final List<(Map<String, Object?>, DateTime)> _requests = [];

  /// The line the running script is on (also when it is not the open one).
  int _runLine = 0;

  /// The window is hidden; only the tray icon is left.
  bool hiddenToTray = false;

  /// "Exit" was chosen: closing must not hide the window to the tray.
  bool quitting = false;
  bool _trayShown = false;
  bool _trayHintShown = false;
  String _trayTipShown = '';
  String _trayMarkShown = '';

  /// A script stopped with an error: the red dot stays on the tray icon
  /// until the window is opened.
  bool trayError = false;

  /// Landmarks on the screen (for the eyes only; kept until the program
  /// quits) and whether they are hidden for now.
  final List<({int x, int y})> landmarks = [];
  bool landmarksHidden = false;

  /// The click map of the last test run (null — none yet).
  ClickMap? clickMap;

  /// Where the time of the last run went (the profiler).
  RunProfile? lastProfile;
  final List<MapAction> _mapActs = [];
  ({int w, int h, Uint8List bgra})? _mapShot;

  /// Items of the tray menu and what each of them does ('' = separator).
  static ({List<String> items, List<String> actions}) trayMenuFor(
      RunState state, String? current, String? running,
      {String stopKey = 'f12'}) {
    final items = <String>['Открыть SmartClicker', ''];
    final actions = <String>['open', ''];
    void add(String item, String action) {
      items.add(item);
      actions.add(action);
    }

    switch (state) {
      case RunState.idle:
        if (current == null) {
          add('!Нет открытого скрипта', '');
        } else {
          add('Запустить «$current»', 'run');
        }
      case RunState.running || RunState.paused:
        add(state == RunState.paused ? 'Продолжить' : 'Пауза', 'pause');
        add('Остановить «${running ?? ''}» (${stopKey.toUpperCase()})', 'stop');
      case RunState.recording || RunState.recCountdown:
        add('Остановить запись', 'stop');
      case RunState.countdown:
        add('Отменить запуск', 'stop');
    }
    add('', '');
    add('Выход', 'quit');
    return (items: items, actions: actions);
  }

  /// Scripts tied to programs (start when the program starts or its window
  /// becomes active).
  final List<AutoRule> autoRules = [];

  /// Scripts tied to files (a neural network wrote a task) and their watch.
  final List<FileRule> fileRules = [];
  final FileWatch _fileWatch = FileWatch();

  /// Started by a file rule and waiting to run (rule, how, since when).
  final List<(FileRule, FileRunMode, DateTime)> _fileQueue = [];

  /// «Сторож»: programs restarted after a crash or a hang while their script
  /// works; the rules that watch now and those whose script the guard stops.
  final List<GuardRule> guardRules = [];
  final GuardWatch _guardWatch = GuardWatch();
  final Set<GuardRule> _guardArmed = Set.identity();
  final Set<GuardRule> _guardStopping = Set.identity();

  /// show("Убито", kills) and pinned variables of the running script: label →
  /// value (on the mini panel and over the editor). Kept after the run.
  final ValueNotifier<Map<String, String>> shown = ValueNotifier(const {});

  /// A file rule asks "run?" (the strip above the pages) and since when.
  (FileRule, DateTime)? fileAsk;

  /// Clipboard history (made on first use), the last clipboard change
  /// seen, a picture being saved, the window to paste into, the queue.
  ClipHistory? _clips;
  Trash? _trash;
  bool _autoBackupBusy = false;
  int _clipSeq = -1;
  bool _clipReading = false;
  WindowInfo? _clipTarget;
  final List<ClipItem> clipQueue = [];
  int clipQueueTotal = 0;

  /// Changes when the clipboard history changes (the «Буфер» page listens).
  final clipVersion = ValueNotifier<int>(0);

  /// This run only in the test mode (a file rule with FileRunMode.test).
  bool _forceDry = false;
  final AutoWatch _autoWatch = AutoWatch();

  /// The rule whose script is running now, and whether the rule paused it.
  AutoRule? _autoOwner;
  bool _autoPaused = false;

  /// Parts of Windows itself that have windows but are not programs.
  static const _systemProcesses = {
    'textinputhost.exe', 'applicationframehost.exe', 'shellexperiencehost.exe',
    'searchhost.exe', 'startmenuexperiencehost.exe', 'systemsettings.exe',
    'lockapp.exe', 'widgets.exe',
  };

  static Set<String>? _builtins;

  /// Names of all built-in functions and constants (both spellings).
  static Set<String> get builtinNames => _builtins ??= ScriptRuntime(
          StubBackend(), {'main': 'check', 'source': ''}, (_) {})
      .interp
      .globals
      .vars
      .keys
      .toSet();

  /// Text the user was told about: the next run of it goes ahead anyway.
  String? _forceText;

  /// Restarts made in a row after errors; a run by the user resets it.
  int _restarts = 0;

  DateTime? _lastAppError;

  /// Size of the mini panel in logical pixels.
  static const miniWidth = 440.0, miniHeight = 92.0;

  /// The main window is shrunk into a small always-on-top panel.
  bool compact = false;

  /// The "ghost" mode of a recording is on (see [AppControllerRecord.setGhost]).
  bool ghost = false;

  /// The ghost of a running script: its clicks and keys reach no program
  /// (see [AppControllerRecord.setRunGhost]).
  bool runGhost = false;

  /// The ghost waits for one action of the script (see setRunGhostOnce).
  bool runGhostOnce = false;
  bool _autoCompact = false;

  /// VK codes of a hotkey such as "f12" or "ctrl+alt+s" (empty if invalid).
  static List<int> comboVks(String combo) {
    if (combo.trim().isEmpty) return const [];
    final out = <int>[];
    for (final part in combo.toLowerCase().split('+')) {
      final vk = vkByName[part.trim()];
      if (vk == null) return const [];
      out.add(vk);
    }
    return out;
  }

  /// "Take coordinates with a click": the next left click anywhere outside
  /// our window copies the cursor position to the clipboard.
  bool picking = false;
  bool _pickBtnDown = false;

  /// 'point' — one click; 'color' — one click for the colour; 'region' /
  /// 'image' — a rectangle (see controller_pick.dart).
  String pickMode = 'point';
  Pt? pickCorner;

  /// The pick was started by a block: it gets the coordinates (as code)
  /// and the colour instead of the clipboard. [_pickLine] — line of the
  /// block: a `use_window` above it makes the coordinates window-relative.
  void Function(List<String> values, String color)? _pickDone;
  int _pickLine = 0;

  /// Mouse buttons at the last poll of a pick; a region is being drawn
  /// with the mouse.
  bool _pickMouse = false, _pickRight = false, _pickDragging = false;

  /// Button presses counted by the hook when the stop frame appeared.
  int _pressesLeft = 0, _pressesRight = 0;

  /// Stop frame of a pick: the screen as it was when the pick started
  /// ([_frozenAt] — its top left corner on the screen); null — none.
  Bitmap? _frozen;
  Pt _frozenAt = (x: 0, y: 0);

  /// Polls (25 ms) left before the screen freezes: the main window first
  /// turns into the mini panel ([_pickCompacted]).
  int _freezeDelay = 0;
  bool _pickCompacted = false;
  Pt? _loupeAt;

  /// The region the user selected last; shown on the "Pictures and text"
  /// page.
  final captured = ValueNotifier<ScreenCapture?>(null);

  /// Asks the interface to open a page ('vision'); it resets this to null.
  final pageRequest = ValueNotifier<String?>(null);

  /// Changes when saved pictures were renamed, replaced or deleted.
  final picturesChanged = ValueNotifier<int>(0);

  /// A line of the open script to show (from "where used"); the editor
  /// scrolls there and sets it back to 0.
  final revealLine = ValueNotifier<int>(0);

  /// "Replace with a snapshot": the picture the next marked region goes to.
  String? _pictureToReplace;

  /// Tells the interface that something changed (the parts of the
  /// controller are extensions and may not call notifyListeners directly).
  void _changed() => notifyListeners();
}
