// Recording of user actions (mouse, keys, text, wheel) and turning them into code.

import 'dart:async';
import 'dart:math' as math;

import '../../platform/backend.dart';
import '../../platform/keys.dart';

/// How mouse movement is recorded.
///  * clicks – only clicks, drags and keys (shortest script);
///  * hover  – also the places where the cursor rested for a while;
///  * full   – the complete trajectory, replayed point by point.
enum RecordMode { clicks, hover, full }

RecordMode recordModeOf(String name) => RecordMode.values
    .firstWhere((m) => m.name == name, orElse: () => RecordMode.clicks);

class RecordOptions {
  final bool percent;
  final bool smart;
  final bool text;
  final RecordMode mode;

  /// Minimal rest time (ms) that counts as "the cursor stopped here".
  final int dwellMs;

  /// Bind actions to the window they happened in (focus_window/use_window).
  final bool window;

  /// With [window]: also require_window("…") — clicks go only into that
  /// window, which is brought to the front if something covers it.
  final bool requireWindow;

  /// Record system-wide combos (Win+..., Alt+Tab, PrintScreen) even while
  /// our own window is the active one: they do not go to our window.
  final bool systemKeys;
  const RecordOptions({
    this.percent = true,
    this.smart = true,
    this.text = true,
    this.mode = RecordMode.clicks,
    this.dwellMs = 500,
    this.window = false,
    this.requireWindow = true,
    this.systemKeys = true,
  });
}

/// How a script should find window [w] again: the process name, or
/// "process|title" when the program has several windows open.
String windowSelector(WindowInfo w, List<WindowInfo> all) {
  final title = w.title.replaceFirst(RegExp(r'^[*●\s]+'), '').trim();
  if (w.process.isEmpty) return title;
  final p = w.process.toLowerCase();
  final several = all.where((x) => x.process.toLowerCase() == p).length > 1;
  return several && title.isNotEmpty ? '${w.process}|$title' : w.process;
}

/// Finds which window binding is in effect at the end of [code]: the
/// argument of the last use_window("..."), or null after use_screen();
/// inside an unclosed `with_window("...") {` — its window.
String? bindingAt(String code) {
  final re = RegExp(r'use_window\(\s*'
      "[\"']([^\"']*)[\"']"
      r'\s*\)|use_screen\(\s*\)|use_window\(\s*(?:null|false)?\s*\)'
      r'|with_?[wW]indow\(\s*'
      "[\"']([^\"']*)[\"']"
      r'[^)]*\)\s*\{|[{}]');
  String? bound;
  var depth = 0;
  final open = <(int, String?)>[]; // with_window blocks: depth, binding before
  for (final m in re.allMatches(code)) {
    final s = m[0]!;
    if (s == '{') {
      depth++;
    } else if (s == '}') {
      depth--;
      if (open.isNotEmpty && open.last.$1 == depth) bound = open.removeLast().$2;
    } else if (m[2] != null) {
      open.add((depth, bound));
      depth++;
      bound = m[2];
    } else {
      bound = m[1];
    }
  }
  return bound;
}

class _Ev {
  final int t;
  final String kind; // md, mu, kd, ku, wh
  final String name; // button or key; wheel: 'v' or 'h'
  final int delta; // wheel: 120 per notch, positive = up / right
  final int x, y;
  final bool own; // happened while our own window was active
  final String? ch; // character the key produced in the active layout
  final WindowInfo? win; // window the action belongs to
  final Rect4? client; // its client area at that moment
  _Ev(this.t, this.kind, this.name, this.x, this.y, this.own,
      {this.ch, this.win, this.client, this.delta = 0});
}

class _Move {
  final int t, x, y;
  const _Move(this.t, this.x, this.y);
}

/// One recorded user action, before it is turned into code.
class _Item {
  final int start, end;
  final String kind; // click, dclick, rclick, hold, drag, key, text, scroll
  final int x, y, x2, y2;
  int delta = 0; // scroll: accumulated wheel delta
  final String button;
  String data; // key combo or typed text
  int endMut;
  final WindowInfo? win;
  final Rect4? client;
  _Item(this.kind, this.start, this.end,
      {this.x = 0,
      this.y = 0,
      this.x2 = 0,
      this.y2 = 0,
      this.button = 'left',
      this.data = '',
      this.win,
      this.client})
      : endMut = end;
}

class _Out {
  final int start, end;
  final List<String> lines;
  _Out(this.start, this.end, this.lines);
}

/// Records mouse and keyboard activity by polling and turns it into script
/// code. Polling is simple and needs no hooks; only the mouse wheel is
/// watched through the backend (it has no state to poll).
class Recorder {
  final PlatformBackend backend;
  /// True while our own window has keyboard focus (its key presses are not
  /// part of the recording).
  final bool Function() ownWindowActive;

  /// True when a screen point is over our own window (clicks and movement
  /// there are not part of the recording). Mouse actions are judged by where
  /// the cursor is, NOT by which window is active: right after pressing
  /// "Record" our window is still active while the user already works
  /// elsewhere, e.g. on the taskbar.
  final bool Function(int x, int y)? overOwnWindow;
  final Set<int> ignoreVks;
  final List<_Ev> _events = [];
  final List<_Move> _moves = [];
  final Map<int, bool> _state = {};
  final Stopwatch _sw = Stopwatch();
  Timer? _timer;
  Pt? _lastPos;
  int _lastMoveT = 0;

  static const _buttons = {'left': 0x01, 'right': 0x02, 'middle': 0x04};

  /// Combos handled by Windows itself, whatever window is active.
  static bool _isSystemCombo(Set<String> mods, String key) =>
      mods.contains('win') ||
      key == 'printscreen' ||
      (mods.contains('alt') && (key == 'tab' || key == 'esc')) ||
      (mods.contains('ctrl') && key == 'esc');

  Recorder(this.backend, this.ownWindowActive, this.ignoreVks,
      {this.overOwnWindow});

  bool get recording => _timer != null;
  int get elapsedMs => _sw.elapsedMilliseconds;
  int get eventCount => _events.length;

  void start() {
    _events.clear();
    _moves.clear();
    _state.clear();
    _lastPos = null;
    // Whatever is held right now is not part of the recording.
    for (final vk in [..._buttons.values, ...recordableVks]) {
      _state[vk] = backend.isVkDown(vk);
    }
    _sw
      ..reset()
      ..start();
    _timer = Timer.periodic(const Duration(milliseconds: 8), (_) => _poll());
    wheelWatched = backend.watchWheel(_onWheel);
  }

  /// False when the wheel could not be watched (it is then not recorded).
  bool wheelWatched = false;

  void _onWheel(int delta, bool horizontal, int x, int y) {
    if (_timer == null || delta == 0) return;
    final own = overOwnWindow?.call(x, y) ?? false;
    final win = own ? null : backend.windowAt(x, y);
    _events.add(_Ev(_sw.elapsedMilliseconds, 'wh', horizontal ? 'h' : 'v', x, y, own,
        delta: delta,
        win: win,
        client: win == null ? null : backend.clientRect(win.handle)));
  }

  void _poll() {
    final t = _sw.elapsedMilliseconds;
    final pos = backend.cursorPos();
    bool? overOwn;
    bool isOverOwn() => overOwn ??= overOwnWindow?.call(pos.x, pos.y) ?? false;

    final last = _lastPos;
    if (last == null ||
        ((pos.x != last.x || pos.y != last.y) && t - _lastMoveT >= 12)) {
      _lastPos = pos;
      _lastMoveT = t;
      if (!isOverOwn()) _moves.add(_Move(t, pos.x, pos.y));
    }

    bool? keysOwn;
    void edge(int vk, String kind, String name) {
      final down = backend.isVkDown(vk);
      if (_state[vk] == down) return;
      _state[vk] = down;
      final own =
          kind == 'm' ? isOverOwn() : (keysOwn ??= ownWindowActive());
      String? ch;
      WindowInfo? win;
      if (down && !own) {
        if (kind == 'm') {
          win = backend.windowAt(pos.x, pos.y);
        } else if (!modifierKeys.contains(name)) {
          ch = backend.charForVk(vk, shift: backend.isVkDown(0x10));
          win = backend.activeWindow();
        }
      }
      _events.add(_Ev(t, '$kind${down ? 'd' : 'u'}', name, pos.x, pos.y, own,
          ch: ch,
          win: win,
          client: win == null ? null : backend.clientRect(win.handle)));
    }

    _buttons.forEach((name, vk) => edge(vk, 'm', name));
    for (final vk in recordableVks) {
      if (ignoreVks.contains(vk)) continue;
      edge(vk, 'k', nameByVk[vk]!);
    }
  }

  /// Stops recording and returns the generated script.
  String stop(RecordOptions o) {
    _timer?.cancel();
    _timer = null;
    backend.unwatchWheel();
    _sw.stop();
    return _Generator(backend, o, _items(o), _moves, _sw.elapsedMilliseconds)
        .build();
  }

  /// Turns raw key/button edges into user-level actions.
  List<_Item> _items(RecordOptions o) {
    final items = <_Item>[];
    final downs = <String, _Ev>{};
    final mods = <String>{};
    // A chord of modifiers only (Alt+Shift, Win) is emitted when released,
    // unless another key was pressed while they were held.
    var chordUsed = false;
    var chordPeak = <String>[];
    // Modifiers in the order they were pressed. Replaying Alt+Shift as
    // "shift, alt" would release Alt on its own and open the window menu.
    final pressed = <String>[];

    for (final e in _events) {
      switch (e.kind) {
        case 'wh':
          if (e.own) continue;
          final last = items.isNotEmpty ? items.last : null;
          // Notches turned in one go, in one direction, become one scroll().
          if (last != null &&
              last.kind == 'scroll' &&
              last.button == e.name &&
              (last.delta > 0) == (e.delta > 0) &&
              e.t - last.endMut < 500 &&
              (last.x - e.x).abs() <= 30 &&
              (last.y - e.y).abs() <= 30) {
            last.delta += e.delta;
            last.endMut = e.t + 20;
          } else {
            items.add(_Item('scroll', e.t, e.t + 20,
                x: e.x, y: e.y, button: e.name, win: e.win, client: e.client)
              ..delta = e.delta);
          }
        case 'md':
          downs[e.name] = e;
        case 'mu':
          final d = downs.remove(e.name);
          if (d == null || d.own) continue;
          final dur = e.t - d.t;
          final moved = (e.x - d.x).abs() > 6 || (e.y - d.y).abs() > 6;
          final kind = moved
              ? 'drag'
              : dur >= 500
                  ? 'hold'
                  : e.name == 'right'
                      ? 'rclick'
                      : 'click';
          final last = items.isNotEmpty ? items.last : null;
          // Two quick clicks at the same spot become a double click.
          if (kind == 'click' &&
              e.name == 'left' &&
              last != null &&
              last.kind == 'click' &&
              last.button == 'left' &&
              (last.x - d.x).abs() <= 4 &&
              (last.y - d.y).abs() <= 4 &&
              d.t - last.end < 350) {
            items.removeLast();
            items.add(_Item('dclick', last.start, e.t,
                x: last.x, y: last.y, win: last.win, client: last.client));
          } else {
            items.add(_Item(kind, d.t, e.t,
                x: d.x,
                y: d.y,
                x2: e.x,
                y2: e.y,
                button: e.name,
                win: d.win,
                client: d.client));
          }
        case 'kd':
          if (modifierKeys.contains(e.name)) {
            mods.add(e.name);
            if (!pressed.contains(e.name)) pressed.add(e.name);
            if (!chordUsed) chordPeak = List.of(pressed);
            continue;
          }
          if (mods.isNotEmpty) chordUsed = true;
          if (e.own && !(o.systemKeys && _isSystemCombo(mods, e.name))) {
            continue;
          }
          final plain = mods.every((m) => m == 'shift');
          if (o.text && plain && e.ch != null) {
            final last = items.isNotEmpty ? items.last : null;
            if (last != null && last.kind == 'text' && e.t - last.endMut < 2000) {
              last.data += e.ch!;
              last.endMut = e.t + 30;
            } else {
              items.add(_Item('text', e.t, e.t + 30,
                  data: e.ch!, win: e.win, client: e.client));
            }
          } else {
            items.add(_Item('key', e.t, e.t + 30,
                // Modifiers go in the order they were really pressed.
                data: [...pressed, e.name].join('+'),
                win: e.win,
                client: e.client));
          }
        case 'ku':
          if (!modifierKeys.contains(e.name)) continue;
          final worthIt = chordPeak.length >= 2 ||
              (chordPeak.length == 1 && chordPeak.first == 'win');
          if (!chordUsed && worthIt && !e.own) {
            // e.g. the keyboard-layout switch (Alt+Shift, Ctrl+Shift).
            items.add(_Item('key', e.t - 30, e.t, data: chordPeak.join('+')));
          }
          chordUsed = true;
          mods.remove(e.name);
          pressed.remove(e.name);
          if (mods.isEmpty) {
            chordUsed = false;
            chordPeak = [];
          }
      }
    }
    return items;
  }
}

/// Second pass: actions + cursor samples -> script text.
class _Generator {
  final PlatformBackend backend;
  final RecordOptions o;
  final List<_Item> items;
  final List<_Move> moves;
  final int totalMs;
  final List<_Out> out = [];

  // Area the coordinates are currently relative to.
  int? _boundHandle;
  late Rect4 _area;
  late final Rect4 _screen;
  late final List<WindowInfo> _allWindows;

  _Generator(this.backend, this.o, this.items, this.moves, this.totalMs) {
    final s = backend.screenSize();
    _screen = (x: 0, y: 0, w: s.w, h: s.h);
    _area = _screen;
    _allWindows = backend.windows();
  }

  static String _esc(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

  /// "Smart pauses": tidy numbers instead of 1437 ms.
  int _round(int ms) {
    if (!o.smart) return ms;
    if (ms < 1000) return ((ms / 50).round() * 50).clamp(50, 1000);
    return (ms / 100).round() * 100;
  }

  String _num(double v) => v.toStringAsFixed(2);
  String _cx(int x) => o.percent && _area.w > 0
      ? '${_num((x - _area.x) * 100 / _area.w)}%'
      : '${x - _area.x}';
  String _cy(int y) => o.percent && _area.h > 0
      ? '${_num((y - _area.y) * 100 / _area.h)}%'
      : '${y - _area.y}';

  String _selector(WindowInfo w) => windowSelector(w, _allWindows);

  bool _bindable(_Item it) =>
      o.window && it.win != null && !it.win!.isShell && it.client != null;

  /// A click on the taskbar / a window thumbnail that only switched to the
  /// window used next: replaced by focus_window().
  bool _isSwitchClick(int i) {
    final it = items[i];
    if (!o.window || it.win == null) return false;
    if (!(it.kind == 'click' || it.kind == 'dclick')) return false;
    if (!(it.win!.isShell && it.win!.title.isEmpty)) return false;
    for (var j = i + 1; j < items.length; j++) {
      final next = items[j];
      if (next.win == null) continue;
      return _bindable(next);
    }
    return false;
  }

  /// Lines that (re)bind coordinates before [it], if its window differs.
  List<String> _bind(_Item it) {
    if (!o.window) return const [];
    if (_bindable(it)) {
      // Keys go to the active window but do not need coordinates; still make
      // sure that window is in front.
      if (it.win!.handle == _boundHandle) {
        _area = it.client!;
        return const [];
      }
      _boundHandle = it.win!.handle;
      _area = it.client!;
      final sel = _esc(_selector(it.win!));
      return [
        'focus_window("$sel")',
        'use_window("$sel")',
        if (o.requireWindow) 'require_window("$sel")',
      ];
    }
    if (it.win == null) return const []; // modifier chord: no window info
    if (_boundHandle != null) {
      _boundHandle = null;
      _area = _screen;
      return ['use_screen()', if (o.requireWindow) 'require_window(null)'];
    }
    return const [];
  }

  String _code(_Item it) {
    final btn = it.button == 'left' ? '' : ', button: "${it.button}"';
    switch (it.kind) {
      case 'click':
        return 'click(${_cx(it.x)}, ${_cy(it.y)}$btn)';
      case 'rclick':
        return 'right_click(${_cx(it.x)}, ${_cy(it.y)})';
      case 'dclick':
        return 'double_click(${_cx(it.x)}, ${_cy(it.y)})';
      case 'hold':
        return 'hold(${_cx(it.x)}, ${_cy(it.y)}, ${_round(it.end - it.start)}$btn)';
      case 'drag':
        return 'drag(${_cx(it.x)}, ${_cy(it.y)}, ${_cx(it.x2)}, ${_cy(it.y2)}, '
            '${_round(it.end - it.start)}$btn)';
      case 'scroll':
        // Script: positive = down; the wheel reports positive = up. A
        // horizontal wheel reports positive = right, as the script does.
        final n = (it.delta / 120).round();
        final amount = it.button == 'h' ? n : -n;
        return 'scroll(${amount == 0 ? (it.delta > 0 ? (it.button == 'h' ? 1 : -1) : (it.button == 'h' ? -1 : 1)) : amount}, '
            '${_cx(it.x)}, ${_cy(it.y)}${it.button == 'h' ? ', horizontal: true' : ''})';
      case 'text':
        return 'type("${_esc(it.data)}")';
      default:
        return 'key("${_esc(it.data)}")';
    }
  }

  Iterable<_Move> _between(int from, int to) =>
      moves.where((m) => m.t > from && m.t < to);

  /// Places where the cursor rested for at least [RecordOptions.dwellMs].
  /// A rest tolerates small hand tremor; rests right where the previous or
  /// the next click happens are skipped (the click already puts the cursor
  /// there).
  void _hovers(int from, int to, {Pt? prev, Pt? next}) {
    const radius = 10;
    const near = 15;
    bool close(_Move m, Pt? p) =>
        p != null && (m.x - p.x).abs() <= near && (m.y - p.y).abs() <= near;
    final seg = _between(from, to).toList();
    var i = 0;
    var first = true;
    while (i < seg.length) {
      final anchor = seg[i];
      var j = i;
      while (j + 1 < seg.length &&
          (seg[j + 1].x - anchor.x).abs() <= radius &&
          (seg[j + 1].y - anchor.y).abs() <= radius) {
        j++;
      }
      final leftAt = j + 1 < seg.length ? seg[j + 1].t : to;
      final rest = seg[j];
      final isLast = j == seg.length - 1;
      if (leftAt - anchor.t >= o.dwellMs &&
          !(first && close(rest, prev)) &&
          !(isLast && close(rest, next))) {
        final start = math.max(from, anchor.t - 250);
        out.add(_Out(start, anchor.t, [
          'move(${_cx(rest.x)}, ${_cy(rest.y)}, duration: ${math.max(anchor.t - start, 50)})'
        ]));
      }
      first = false;
      i = j + 1;
    }
  }

  /// The whole trajectory between two moments, as mouse_path() lines.
  void _path(int from, int to) {
    final seg = _between(from, to).toList();
    if (seg.isEmpty) return;
    const perLine = 10;
    var prevT = seg.first.t;
    for (var i = 0; i < seg.length; i += perLine) {
      final chunk = seg.sublist(i, math.min(i + perLine, seg.length));
      final start = prevT;
      final sb = StringBuffer();
      for (final m in chunk) {
        if (sb.isNotEmpty) sb.write(' ');
        final x = o.percent && _area.w > 0
            ? _num((m.x - _area.x) * 100 / _area.w)
            : '${m.x - _area.x}';
        final y = o.percent && _area.h > 0
            ? _num((m.y - _area.y) * 100 / _area.h)
            : '${m.y - _area.y}';
        sb.write('$x,$y,${m.t - prevT}');
        prevT = m.t;
      }
      out.add(_Out(start, prevT,
          ['mouse_path("$sb"${o.percent ? ', unit: "%"' : ''})']));
    }
  }

  void _movement(int from, int to, {Pt? prev, Pt? next}) {
    if (to <= from) return;
    switch (o.mode) {
      case RecordMode.clicks:
        break;
      case RecordMode.hover:
        _hovers(from, to, prev: prev, next: next);
      case RecordMode.full:
        _path(from, to);
    }
  }

  String build() {
    var prevEnd = 0;
    Pt? prevPt;
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      if (_isSwitchClick(i)) {
        // Keep the time it took, drop the click.
        continue;
      }
      final mouse = it.kind != 'key' && it.kind != 'text';
      _movement(prevEnd, it.start,
          prev: prevPt, next: mouse ? (x: it.x, y: it.y) : null);
      if (mouse) {
        prevPt = it.kind == 'drag' ? (x: it.x2, y: it.y2) : (x: it.x, y: it.y);
      }
      final lines = [..._bind(it)];
      if (o.mode == RecordMode.full && it.kind == 'drag') {
        // Follow the real trajectory of the drag instead of a straight line.
        final btn = it.button == 'left' ? '' : ', button: "${it.button}"';
        out.add(_Out(it.start, it.start,
            [...lines, 'mouse_down(${_cx(it.x)}, ${_cy(it.y)}$btn)']));
        _path(it.start, it.end);
        out.add(_Out(
            it.end, it.end, ['mouse_up(${_cx(it.x2)}, ${_cy(it.y2)}$btn)']));
      } else {
        out.add(_Out(it.start, it.endMut, [...lines, _code(it)]));
      }
      prevEnd = it.endMut;
    }
    if (items.isNotEmpty || o.mode != RecordMode.clicks) {
      _movement(prevEnd, totalMs, prev: prevPt);
    }

    final sb = StringBuffer();
    var end = -1;
    for (final a in out) {
      if (end >= 0) {
        var gap = a.start - end;
        if (o.smart) gap = gap < 25 ? 0 : _round(gap);
        if (gap >= (o.smart ? 50 : 10)) sb.writeln('wait($gap)');
      }
      a.lines.forEach(sb.writeln);
      end = a.end;
    }
    if (_boundHandle != null) {
      sb.writeln('use_screen()');
      if (o.requireWindow) sb.writeln('require_window(null)');
    }
    return sb.toString();
  }
}
