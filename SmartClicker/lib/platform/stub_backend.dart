// Backend without a real OS: for tests and platforms not supported yet.

import 'dart:io' show exit;
import 'dart:typed_data';

import 'backend.dart';

/// Backend for platforms that are not implemented yet, and for tests:
/// records input calls instead of performing them.
class StubBackend implements PlatformBackend {
  final List<String> calls = [];
  int cx = 0, cy = 0;
  int pixelColor = 0x000000;
  List<WindowInfo> windowList = [];
  WindowInfo? active;
  String clipboard = '';

  @override
  String get name => 'stub';
  @override
  ({int w, int h}) screenSize() => (w: 1920, h: 1080);
  @override
  Pt cursorPos() => (x: cx, y: cy);
  @override
  void moveTo(int x, int y) {
    cx = x;
    cy = y;
    calls.add('move $x,$y');
  }

  @override
  void mouseButton(String button, bool down) =>
      calls.add('${down ? 'down' : 'up'} $button');
  @override
  void scroll(int amount, {bool horizontal = false}) =>
      calls.add('scroll $amount');
  @override
  void keyEvent(String key, bool down) =>
      calls.add('${down ? 'keydown' : 'keyup'} $key');
  @override
  void typeText(String text, {bool layoutKeys = true}) => calls.add('type $text');
  @override
  int pixel(int x, int y) => pixelColor;
  /// What [readText] returns (tests).
  String screenText = '';
  @override
  String readText(int x, int y, int w, int h, {String lang = '', int scale = 0}) {
    calls.add('ocr $x $y $w $h');
    return screenText;
  }

  @override
  String ocrImage(Uint8List bgra, int w, int h, {String lang = '', int scale = 0}) =>
      screenText;
  @override
  void activateSelf() {}
  Rect4? frame;
  @override
  void showFrame(int x, int y, int w, int h) => frame = (x: x, y: y, w: w, h: h);
  @override
  void hideFrame() => frame = null;

  /// Set while the wheel is watched; tests call it to turn the wheel.
  void Function(int delta, bool horizontal, int x, int y)? wheel;
  @override
  bool watchWheel(void Function(int delta, bool horizontal, int x, int y) onWheel) {
    wheel = onWheel;
    return true;
  }

  @override
  void unwatchWheel() => wheel = null;

  /// The combos last passed to [holdBackKeys].
  List<List<int>> heldBack = const [];
  @override
  bool holdBackKeys(List<List<int>> combos) {
    heldBack = combos;
    return true;
  }

  @override
  void stopKeyHook() => heldBack = const [];

  @override
  bool isUserKeyDown(int vk) => isVkDown(vk);

  bool userMouseWatched = false;
  ({int x, int y, int ageMs})? userMouse;
  @override
  bool watchUserMouse(bool on) => userMouseWatched = on;
  @override
  ({int x, int y, int ageMs})? lastUserMouse() => userMouseWatched ? userMouse : null;

  String? startupCommand;
  bool startupDisabled = false;
  @override
  ({String? command, bool disabled}) startupEntry() =>
      (command: startupCommand, disabled: startupDisabled);
  @override
  bool setStartupEntry(String? command) {
    startupCommand = command;
    startupDisabled = false;
    return true;
  }

  bool elevated = false;
  Map<int, bool?> elevatedPids = {};

  @override
  bool isElevated() => elevated;

  @override
  bool? isProcessElevated(int pid) => elevatedPids[pid] ?? false;

  @override
  bool restartElevated() => false;

  @override
  List<String> ocrLanguages() => const ['ru', 'en-US'];

  // Tray: remembered for tests.
  String? trayTip;
  void Function(String)? trayEvents;
  final List<String> balloons = [];
  bool mainHidden = false, minimized = false;
  int menuChoice = -1;
  List<String> lastMenu = const [];

  @override
  bool showTray(String tip, void Function(String event) onEvent) {
    trayTip = tip;
    trayEvents = onEvent;
    return true;
  }

  @override
  void hideTray() => trayTip = null;

  @override
  void trayBalloon(String title, String text) => balloons.add('$title: $text');

  @override
  int trayMenu(List<String> items, {int bold = -1}) {
    lastMenu = items;
    return menuChoice;
  }

  @override
  void hideMainWindow() => mainHidden = true;

  @override
  void showMainWindow() => mainHidden = minimized = false;

  @override
  bool isMainMinimized() => minimized;

  @override
  bool isMainVisible() => !mainHidden;

  @override
  Uint8List capture(int x, int y, int w, int h) {
    final out = Uint8List(w * h * 4);
    for (var i = 0; i < w * h; i++) {
      out[i * 4] = pixelColor & 0xFF;
      out[i * 4 + 1] = (pixelColor >> 8) & 0xFF;
      out[i * 4 + 2] = (pixelColor >> 16) & 0xFF;
      out[i * 4 + 3] = 0xFF;
    }
    return out;
  }

  @override
  List<WindowInfo> windows() => windowList;
  @override
  WindowInfo? activeWindow() => active;
  @override
  int pidAt(int x, int y) => windowAt(x, y)?.pid ?? 0;

  @override
  WindowInfo? windowAt(int x, int y) {
    for (final w in windowList) {
      if (x >= w.x && x < w.x + w.w && y >= w.y && y < w.y + w.h) return w;
    }
    return null;
  }

  @override
  bool focusWindow(int handle) {
    calls.add('focus $handle');
    for (final w in windowList) {
      if (w.handle == handle) active = w;
    }
    return true;
  }
  @override
  bool setWindowBounds(int handle, int x, int y, int w, int h) => true;
  @override
  Rect4? clientRect(int handle) {
    for (final w in windowList) {
      if (w.handle == handle) return (x: w.x, y: w.y, w: w.w, h: w.h);
    }
    return null;
  }

  @override
  List<String> processes() => windowList.map((w) => w.process).toList();
  @override
  int killProcess(String name) => 0;
  @override
  int? batteryLevel() => null;
  @override
  bool? isCharging() => null;
  @override
  bool networkConnected() => true;

  /// Fake CPU counters: every call advances the clock by 1 s of wall time
  /// on 4 processors; the system is 25% busy, "game.exe" uses 10% of all
  /// processors.
  int _cpuCalls = 0, _procCalls = 0;
  @override
  ({int idle, int total})? cpuTimes() {
    _cpuCalls++;
    return (idle: _cpuCalls * 30000000, total: _cpuCalls * 40000000);
  }

  @override
  Map<int, int> processCpuTimes(String name) {
    final n = name.toLowerCase();
    if (n != 'game' && n != 'game.exe') return {};
    _procCalls++;
    return {42: _procCalls * 4000000};
  }

  @override
  ({int total, int free})? memoryStatus() =>
      (total: 16 << 30, free: 4 << 30);

  @override
  int? processMemory(String name) {
    final n = name.toLowerCase();
    return n == 'game' || n == 'game.exe' ? 300 << 20 : null;
  }

  @override
  bool systemPower(String action) {
    calls.add('power $action');
    return true;
  }
  @override
  String getClipboard() => clipboard;
  @override
  void setClipboard(String text) => clipboard = text;
  final Set<int> downVks = {};
  final Map<int, String> chars = {};
  @override
  bool isVkDown(int vk) => downVks.contains(vk);
  @override
  String? charForVk(int vk, {required bool shift}) => chars[vk];
  @override
  String? pickFile({required bool save, required String title, String defaultName = '', String ext = 'zip'}) => null;
  @override
  String? pickFolder({required String title, String? start}) => null;
  @override
  bool restartSelf() => false;
  @override
  void showMarker(int x, int y) {}
  @override
  void hideMarker() {}
  Rect4? panel;
  @override
  bool enterPanel(int? x, int? y, int w, int h) {
    panel = (x: x ?? 1920 - w, y: y ?? 0, w: w, h: h);
    return true;
  }

  @override
  void leavePanel({bool activate = true}) => panel = null;
  @override
  void movePanel(int x, int y) {
    final p = panel;
    if (p != null) panel = (x: x, y: y, w: p.w, h: p.h);
  }

  @override
  Rect4? panelBounds() => panel;
  @override
  void releaseAll() => calls.add('releaseAll');

  @override
  Never endProcess() => exit(0);
}
