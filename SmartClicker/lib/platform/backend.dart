// Interface to the operating system: input, screen, windows, processes, system.
// Every OS has its own implementation (windows/, stub for tests).

import 'dart:io';
import 'dart:typed_data';

import 'stub_backend.dart';
import 'windows/windows_backend.dart';

class WindowInfo {
  final int handle;
  final String title;
  final String process;
  final int pid;
  final int x, y, w, h;
  const WindowInfo(
      this.handle, this.title, this.process, this.pid, this.x, this.y, this.w, this.h);

  /// Matches by process name (with or without .exe) or by part of the title.
  /// "process|title part" requires both (to pick one of several windows of
  /// the same program).
  bool matches(String query) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return false;
    final p = process.toLowerCase();
    final bar = q.indexOf('|');
    if (bar >= 0) {
      final qp = q.substring(0, bar).trim();
      final qt = q.substring(bar + 1).trim();
      final procOk = qp.isEmpty || p == qp || p == '$qp.exe';
      return procOk && title.toLowerCase().contains(qt);
    }
    if (p == q || p == '$q.exe') return true;
    return title.toLowerCase().contains(q);
  }

  /// Taskbar, window thumbnails, desktop: not a window to bind a script to.
  bool get isShell =>
      process.toLowerCase() == 'explorer.exe' &&
      (title.isEmpty || title == 'Program Manager');

  Map<String, Object?> toMap() => {
        'title': title,
        'process': process,
        'pid': pid,
        'x': x,
        'y': y,
        'w': w,
        'h': h,
      };
}

typedef Rect4 = ({int x, int y, int w, int h});
typedef Pt = ({int x, int y});

/// Everything the engine needs from the operating system.
abstract class PlatformBackend {
  String get name;

  /// Size of the primary screen in physical pixels.
  ({int w, int h}) screenSize();
  Pt cursorPos();
  void moveTo(int x, int y);

  /// [button]: left | right | middle.
  void mouseButton(String button, bool down);

  /// Positive [amount] scrolls down, negative scrolls up (wheel notches).
  void scroll(int amount, {bool horizontal = false});

  /// [key] is a name from `keys.dart`. Throws [ArgumentError] if unknown.
  void keyEvent(String key, bool down);
  void typeText(String text);

  /// Colour at a screen point as 0xRRGGBB.
  int pixel(int x, int y);

  /// Raw BGRA bytes of a screen region.
  Uint8List capture(int x, int y, int w, int h);

  /// Text recognized in a screen region, lines separated by a line break.
  /// [lang]: "ru", "en-US"...; empty = the languages of the system.
  /// [scale]: enlargement before recognition, 0 = choose automatically.
  String readText(int x, int y, int w, int h, {String lang = '', int scale = 0});

  /// The same for a picture in memory (top-down BGRA).
  String ocrImage(Uint8List bgra, int w, int h, {String lang = '', int scale = 0});

  /// Brings the application's own main window to the front.
  void activateSelf();

  List<WindowInfo> windows();
  WindowInfo? activeWindow();

  /// Process id of whatever is under a screen point (cheap; 0 if nothing).
  int pidAt(int x, int y);

  /// Top-level window under a screen point.
  WindowInfo? windowAt(int x, int y);
  bool focusWindow(int handle);
  bool setWindowBounds(int handle, int x, int y, int w, int h);

  /// Client area of a window in screen coordinates.
  Rect4? clientRect(int handle);

  List<String> processes();
  int killProcess(String name);

  int? batteryLevel();
  bool? isCharging();
  bool networkConnected();

  /// System CPU time counters in 100 ns units: idle and total (kernel +
  /// user, all processors). Null when unavailable.
  ({int idle, int total})? cpuTimes();

  /// Kernel + user CPU time (100 ns units) of every process named [name]
  /// (with or without .exe), by pid. Empty when none runs.
  Map<int, int> processCpuTimes(String name);

  /// Physical memory, bytes.
  ({int total, int free})? memoryStatus();

  /// Working set (bytes) of all processes named [name] together; null when
  /// none runs.
  int? processMemory(String name);

  /// "lock", "sleep", "hibernate", "shutdown", "restart" or "logoff".
  /// False when the system refused.
  bool systemPower(String action);

  /// This program runs "as administrator".
  bool isElevated();

  /// Whether a process runs as administrator; null when Windows does not
  /// tell (for an ordinary program that means it is elevated or a system
  /// one).
  bool? isProcessElevated(int pid);

  /// Starts this program again as administrator (Windows asks the user).
  /// True if the new copy was started; this one should then quit.
  bool restartElevated();

  /// Languages the built-in Windows text recognition knows ("ru", "en-US").
  List<String> ocrLanguages();

  String getClipboard();
  void setClipboard(String text);

  /// Native "open" / "save as" dialog for a file with extension [ext]; null if cancelled
  /// or not supported.
  String? pickFile({required bool save, required String title, String defaultName = '', String ext = 'zip'});

  /// The system "Select folder" dialog opened in [start]; null if cancelled.
  String? pickFolder({required String title, String? start});

  /// Starts a new copy of the program (it waits until this one quits).
  bool restartSelf();

  /// Shows a click-through red ring on the screen at a point (debugging).
  void showMarker(int x, int y);
  void hideMarker();

  /// Shows a click-through frame around a screen rectangle (region
  /// selection). The frame is drawn outside the rectangle, so a screenshot
  /// of the rectangle itself never contains it.
  void showFrame(int x, int y, int w, int h);
  void hideFrame();

  /// Turns the application's own main window into a small borderless panel
  /// that stays above other windows and does not take the keyboard focus.
  /// [x], [y] null = top right corner of the screen. Sizes are in physical
  /// pixels. Returns false if not supported.
  bool enterPanel(int? x, int? y, int w, int h);

  /// Restores the main window after [enterPanel] and brings it to the front.
  /// With [activate] false it does not take the focus.
  void leavePanel({bool activate = true});
  void movePanel(int x, int y);

  /// Current bounds of the panel, or null when the window is not a panel.
  Rect4? panelBounds();

  /// Starts reporting mouse wheel turns anywhere on the screen (recorder).
  /// [delta]: 120 per notch, positive = away from the user (up / right).
  /// Returns false when the system gives no way to watch the wheel.
  bool watchWheel(void Function(int delta, bool horizontal, int x, int y) onWheel);
  void unwatchWheel();

  /// Icon in the notification area (system tray). [onEvent] gets 'open'
  /// (left click) and 'menu' (right click). Calling again updates the
  /// tooltip. Returns false if not supported.
  bool showTray(String tip, void Function(String event) onEvent);
  void hideTray();

  /// A balloon / notification next to the tray icon.
  void trayBalloon(String title, String text);

  /// Menu at the mouse pointer: '' = separator, a leading '!' = greyed out.
  /// Returns the index of the chosen item or -1.
  int trayMenu(List<String> items, {int bold = -1});

  /// Hides the main window together with its taskbar button, and shows it
  /// again in front.
  void hideMainWindow();
  void showMainWindow();
  bool isMainMinimized();

  /// The main window is shown (not hidden to the tray).
  bool isMainVisible();

  /// Physical state of a virtual key / mouse button (hotkeys, recorder).
  /// Keys held back by [holdBackKeys] count as down too.
  bool isVkDown(int vk);

  /// Keeps the program's hotkeys away from other programs: a press that
  /// completes one of [combos] (VK lists, modifiers first) does not reach
  /// the active window. Calling again replaces the list; empty = hold back
  /// nothing. Returns false when keys cannot be held back (hotkeys still
  /// work, but the active window gets them too).
  bool holdBackKeys(List<List<int>> combos);

  /// The key is held by the user (or another program), not pressed by our
  /// own scripts: a script pressing F12 must not trigger the stop hotkey.
  bool isUserKeyDown(int vk);

  /// Starts / stops watching where the USER moves the mouse (moves made by
  /// our scripts are not counted). False if it cannot be watched.
  bool watchUserMouse(bool on);

  /// Where the user last moved the mouse and how long ago, or null when no
  /// move of the user was seen since [watchUserMouse] was turned on.
  ({int x, int y, int ageMs})? lastUserMouse();

  /// Removes the keyboard hook of [holdBackKeys] (on exit).
  void stopKeyHook();

  /// Start with the system: the command registered for this program at
  /// logon (null if none) and whether the user turned it off elsewhere
  /// (Task Manager → Startup apps).
  ({String? command, bool disabled}) startupEntry();

  /// Registers [command] to run at logon (null removes it); it is also
  /// turned back on if it was turned off in Task Manager. False on failure.
  bool setStartupEntry(String? command);

  /// Printable character that key [vk] produces in the keyboard layout of
  /// the active window, or null (used by the recorder to capture text).
  String? charForVk(int vk, {required bool shift});

  /// Releases every key and mouse button that is currently held down.
  void releaseAll();

  /// Ends this process at once, without the usual shutdown (which can hang
  /// after a system file dialog). Everything must be saved before.
  Never endProcess();
}

PlatformBackend createBackend() =>
    Platform.isWindows ? WindowsBackend() : StubBackend();
