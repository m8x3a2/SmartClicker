// Starting together with Windows: the command written to the system's list
// of programs to start at logon, and what the current entry means.

/// Argument the program gets when Windows starts it at logon.
const autostartArg = '--autostart';

/// The command for the logon list: this exe, quoted (paths with spaces).
String startupCommand(String exe) => '"$exe" $autostartArg';

/// What the logon entry of SmartClicker says about this copy.
class StartupInfo {
  /// There is an entry and Windows will run it.
  final bool on;

  /// The entry starts this very exe (not another copy somewhere else).
  final bool ours;

  /// The entry exists but the user turned it off (Task Manager → Startup).
  final bool disabled;

  /// The exe the entry starts when it is not this one.
  final String? otherPath;

  const StartupInfo({this.on = false, this.ours = false, this.disabled = false, this.otherPath});

  /// Starts with Windows, and starts this copy.
  bool get active => on && ours;
}

StartupInfo describeStartup(String? command, {required bool disabled, required String exe}) {
  if (command == null || command.trim().isEmpty) return const StartupInfo();
  final path = _exeOf(command);
  final ours = path.toLowerCase() == exe.toLowerCase();
  return StartupInfo(
      on: !disabled, ours: ours, disabled: disabled, otherPath: ours ? null : path);
}

/// The program part of a command line: `"C:\a b\x.exe" --arg` -> `C:\a b\x.exe`.
String _exeOf(String command) {
  final c = command.trim();
  if (c.startsWith('"')) {
    final end = c.indexOf('"', 1);
    return end > 0 ? c.substring(1, end) : c.substring(1);
  }
  final space = c.indexOf(' ');
  return space > 0 ? c.substring(0, space) : c;
}
