// Calling COM / WinRT objects through their raw vtables from dart:ffi:
// method slots, Release and GUIDs. Used by OCR and the folder dialog.

import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Method number [index] of the COM object [obj] (0 QueryInterface,
/// 1 AddRef, 2 Release, then the interface's own methods in order).
Pointer<NativeFunction<T>> comSlot<T extends Function>(Pointer<Void> obj, int index) =>
    Pointer.fromAddress(obj.cast<Pointer<IntPtr>>().value[index]);

/// IUnknown::Release; a null object is fine.
int comRelease(Pointer<Void> obj) => obj == nullptr
    ? 0
    : comSlot<Uint32 Function(Pointer<Void>)>(obj, 2)
        .asFunction<int Function(Pointer<Void>)>()(obj);

/// A GUID such as "dc1c5a9c-e88a-4dde-a5a1-60f82a20aef7" in memory
/// (free it with calloc.free).
Pointer<Uint8> guidBytes(String s) {
  final hex = s.replaceAll('-', '');
  final g = calloc<Uint8>(16);
  int b(int i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  const order = [3, 2, 1, 0, 5, 4, 7, 6, 8, 9, 10, 11, 12, 13, 14, 15];
  for (var i = 0; i < 16; i++) {
    g[i] = b(order[i]);
  }
  return g;
}
