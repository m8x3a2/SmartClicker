// The standard Windows "Select folder" dialog (IFileOpenDialog with
// FOS_PICKFOLDERS), called through raw COM vtables.

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'com.dart';

final _ole32 = DynamicLibrary.open('ole32.dll');
final _shell32 = DynamicLibrary.open('shell32.dll');

final _coCreateInstance = _ole32.lookupFunction<
    Int32 Function(Pointer<Uint8>, Pointer<Void>, Uint32, Pointer<Uint8>, Pointer<Pointer<Void>>),
    int Function(Pointer<Uint8>, Pointer<Void>, int, Pointer<Uint8>,
        Pointer<Pointer<Void>>)>('CoCreateInstance');
final _coTaskMemFree =
    _ole32.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('CoTaskMemFree');
final _shCreateItem = _shell32.lookupFunction<
    Int32 Function(Pointer<Utf16>, Pointer<Void>, Pointer<Uint8>, Pointer<Pointer<Void>>),
    int Function(Pointer<Utf16>, Pointer<Void>, Pointer<Uint8>,
        Pointer<Pointer<Void>>)>('SHCreateItemFromParsingName');

const _clsidFileOpenDialog = 'dc1c5a9c-e88a-4dde-a5a1-60f82a20aef7';
const _iidFileOpenDialog = 'd57c7288-d4ad-4768-be02-9d969532d960';
const _iidShellItem = '43826d1e-e718-42ee-bc55-a1e261c37bfe';

// IFileDialog vtable slots (after IUnknown 0-2 and IModalWindow::Show 3).
const _show = 3, _setOptions = 9, _getOptions = 10, _setFolder = 12, _setTitle = 17, _getResult = 20;
const _getDisplayName = 5; // IShellItem
const _sigdnFileSysPath = 0x80058000;

/// Asks for a folder; [owner] is the window the dialog belongs to,
/// [start] the folder it opens in. Null when cancelled.
String? pickFolderDialog({required int owner, required String title, String? start}) {
  final clsid = guidBytes(_clsidFileOpenDialog), iid = guidBytes(_iidFileOpenDialog);
  final out = calloc<Pointer<Void>>();
  final titlePtr = title.toNativeUtf16();
  Pointer<Void> dialog = nullptr, result = nullptr;
  try {
    // CLSCTX_INPROC_SERVER; the UI thread is an STA (the Flutter runner).
    if (_coCreateInstance(clsid, nullptr, 1, iid, out) < 0) return null;
    dialog = out.value;
    final opts = calloc<Uint32>();
    try {
      comSlot<Int32 Function(Pointer<Void>, Pointer<Uint32>)>(dialog, _getOptions)
          .asFunction<int Function(Pointer<Void>, Pointer<Uint32>)>()(dialog, opts);
      // FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST
      comSlot<Int32 Function(Pointer<Void>, Uint32)>(dialog, _setOptions)
          .asFunction<int Function(Pointer<Void>, int)>()(dialog, opts.value | 0x20 | 0x40 | 0x800);
    } finally {
      calloc.free(opts);
    }
    comSlot<Int32 Function(Pointer<Void>, Pointer<Utf16>)>(dialog, _setTitle)
        .asFunction<int Function(Pointer<Void>, Pointer<Utf16>)>()(dialog, titlePtr);
    if (start != null) _setStartFolder(dialog, start);
    final shown = comSlot<Int32 Function(Pointer<Void>, IntPtr)>(dialog, _show)
        .asFunction<int Function(Pointer<Void>, int)>()(dialog, owner);
    if (shown < 0) return null; // cancelled
    if (comSlot<Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>)>(dialog, _getResult)
            .asFunction<int Function(Pointer<Void>, Pointer<Pointer<Void>>)>()(dialog, out) <
        0) {
      return null;
    }
    result = out.value;
    final name = calloc<Pointer<Utf16>>();
    try {
      if (comSlot<Int32 Function(Pointer<Void>, Uint32, Pointer<Pointer<Utf16>>)>(result, _getDisplayName)
              .asFunction<int Function(Pointer<Void>, int, Pointer<Pointer<Utf16>>)>()(
                  result, _sigdnFileSysPath, name) <
          0) {
        return null;
      }
      final path = name.value.toDartString();
      _coTaskMemFree(name.value.cast());
      return path;
    } finally {
      calloc.free(name);
    }
  } finally {
    comRelease(result);
    comRelease(dialog);
    calloc.free(clsid);
    calloc.free(iid);
    calloc.free(out);
    calloc.free(titlePtr);
  }
}

void _setStartFolder(Pointer<Void> dialog, String path) {
  final p = path.toNativeUtf16();
  final iid = guidBytes(_iidShellItem);
  final item = calloc<Pointer<Void>>();
  try {
    if (_shCreateItem(p, nullptr, iid, item) >= 0) {
      comSlot<Int32 Function(Pointer<Void>, Pointer<Void>)>(dialog, _setFolder)
          .asFunction<int Function(Pointer<Void>, Pointer<Void>)>()(dialog, item.value);
      comRelease(item.value);
    }
  } finally {
    calloc.free(p);
    calloc.free(iid);
    calloc.free(item);
  }
}
