// Start with Windows: the value "SmartClicker" in HKCU\...\Run (no
// administrator rights needed) and the on/off flag Task Manager keeps for it.
// ignore_for_file: non_constant_identifier_names
part of 'windows_backend.dart';

const _hkcu = -0x7FFFFFFF; // HKEY_CURRENT_USER, sign-extended like in C
const _runKey = r'Software\Microsoft\Windows\CurrentVersion\Run';
const _approvedKey = r'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';
const _entryName = 'SmartClicker';

final _advapi32 = DynamicLibrary.open('advapi32.dll');

final _RegGetValueW = _advapi32.lookupFunction<
    Int32 Function(IntPtr, Pointer<Utf16>, Pointer<Utf16>, Uint32, Pointer<Uint32>,
        Pointer<Uint8>, Pointer<Uint32>),
    int Function(int, Pointer<Utf16>, Pointer<Utf16>, int, Pointer<Uint32>, Pointer<Uint8>,
        Pointer<Uint32>)>('RegGetValueW');

final _RegSetKeyValueW = _advapi32.lookupFunction<
    Int32 Function(IntPtr, Pointer<Utf16>, Pointer<Utf16>, Uint32, Pointer<Uint8>, Uint32),
    int Function(int, Pointer<Utf16>, Pointer<Utf16>, int, Pointer<Uint8>, int)>('RegSetKeyValueW');

final _RegDeleteKeyValueW = _advapi32.lookupFunction<
    Int32 Function(IntPtr, Pointer<Utf16>, Pointer<Utf16>),
    int Function(int, Pointer<Utf16>, Pointer<Utf16>)>('RegDeleteKeyValueW');

/// Raw bytes of a registry value of HKCU, or null when there is none.
/// [types]: RRF_RT_REG_SZ (2) or RRF_RT_REG_BINARY (8).
Uint8List? _regRead(String key, String name, int types) {
  final k = key.toNativeUtf16(), n = name.toNativeUtf16();
  final size = calloc<Uint32>()..value = 4096;
  final buf = calloc<Uint8>(4096);
  try {
    if (_RegGetValueW(_hkcu, k, n, types, nullptr, buf, size) != 0) return null;
    return Uint8List.fromList(buf.asTypedList(size.value));
  } finally {
    for (final p in [k, n, size, buf]) {
      calloc.free(p);
    }
  }
}

mixin _StartupEntry implements PlatformBackend {
  @override
  ({String? command, bool disabled}) startupEntry() {
    final raw = _regRead(_runKey, _entryName, 2);
    String? command;
    if (raw != null) {
      final units = Uint16List.sublistView(raw, 0, raw.length & ~1);
      final end = units.indexOf(0);
      command = String.fromCharCodes(end < 0 ? units : units.sublist(0, end));
    }
    // Task Manager keeps 12 bytes per entry: an odd first byte = turned off.
    final flag = _regRead(_approvedKey, _entryName, 8);
    return (command: command, disabled: flag != null && flag.isNotEmpty && flag[0].isOdd);
  }

  @override
  bool setStartupEntry(String? command) {
    final k = _runKey.toNativeUtf16(), n = _entryName.toNativeUtf16();
    final approved = _approvedKey.toNativeUtf16();
    try {
      // Turned off in Task Manager earlier: turning on here must win.
      _RegDeleteKeyValueW(_hkcu, approved, n);
      if (command == null) {
        final r = _RegDeleteKeyValueW(_hkcu, k, n);
        return r == 0 || r == 2; // ERROR_FILE_NOT_FOUND: there was none
      }
      final data = command.toNativeUtf16();
      try {
        return _RegSetKeyValueW(_hkcu, k, n, 1, data.cast(), (command.length + 1) * 2) == 0;
      } finally {
        calloc.free(data);
      }
    } finally {
      calloc.free(k);
      calloc.free(n);
      calloc.free(approved);
    }
  }
}
