// Minimal bindings to the ONNX Runtime C API (onnxruntime.dll / .so): just
// enough to run a model with float32 tensors on the CPU. The functions are
// taken from the OrtApi table by index; these indices are part of the stable
// ABI (the table only grows at the end).
// ignore_for_file: non_constant_identifier_names

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

class OrtException implements Exception {
  final String message;
  OrtException(this.message);
  @override
  String toString() => message;
}

typedef _P = Pointer<Void>;
typedef _PP = Pointer<Pointer<Void>>;

const _apiVersion = 11; // ONNX Runtime 1.11+; nothing newer is used here

class OrtTensor {
  final Float32List data;
  final List<int> shape;
  OrtTensor(this.data, this.shape);
}

/// One loaded copy of the runtime.
class Ort {
  final Pointer<IntPtr> _api;
  late final _P _env;
  late final _P _mem;
  late final _P _alloc;

  Ort._(this._api);

  /// Loads the library at [path]. Throws [OrtException] if it cannot be used.
  factory Ort.open(String path) {
    final DynamicLibrary lib;
    try {
      lib = DynamicLibrary.open(path);
    } catch (e) {
      throw OrtException('не удалось загрузить $path: $e');
    }
    final base = lib.lookupFunction<Pointer<IntPtr> Function(),
        Pointer<IntPtr> Function()>('OrtGetApiBase')();
    if (base == nullptr) throw OrtException('ONNX Runtime: нет OrtGetApiBase');
    final api = Pointer<NativeFunction<Pointer<IntPtr> Function(Uint32)>>.fromAddress(
            base[0])
        .asFunction<Pointer<IntPtr> Function(int)>()(_apiVersion);
    if (api == nullptr) {
      throw OrtException('ONNX Runtime в $path слишком старый');
    }
    final ort = Ort._(api);
    final out = calloc<Pointer<Void>>();
    final id = 'smartclicker'.toNativeUtf8();
    try {
      // CreateEnv(level = WARNING, logid, out)
      ort._check(ort._fn<IntPtr Function(Int32, Pointer<Utf8>, _PP)>(3)
          .asFunction<int Function(int, Pointer<Utf8>, _PP)>()(2, id, out));
      ort._env = out.value;
      // CreateCpuMemoryInfo(OrtArenaAllocator = 1, OrtMemTypeDefault = 0, out)
      ort._check(ort._fn<IntPtr Function(Int32, Int32, _PP)>(69)
          .asFunction<int Function(int, int, _PP)>()(1, 0, out));
      ort._mem = out.value;
      ort._check(ort._fn<IntPtr Function(_PP)>(78)
          .asFunction<int Function(_PP)>()(out));
      ort._alloc = out.value;
    } finally {
      calloc.free(out);
      calloc.free(id);
    }
    return ort;
  }

  Pointer<NativeFunction<T>> _fn<T extends Function>(int index) =>
      Pointer.fromAddress(_api[index]);

  /// Turns a non-null OrtStatus into an exception.
  void _check(int status) {
    if (status == 0) return;
    final msg = _fn<Pointer<Utf8> Function(IntPtr)>(2)
        .asFunction<Pointer<Utf8> Function(int)>()(status)
        .toDartString();
    _fn<Void Function(IntPtr)>(93).asFunction<void Function(int)>()(status);
    throw OrtException('ONNX Runtime: $msg');
  }

  void _release(int index, _P p) {
    if (p != nullptr) _fn<Void Function(_P)>(index).asFunction<void Function(_P)>()(p);
  }

  OrtSession session(String modelPath, {int threads = 4}) {
    final out = calloc<Pointer<Void>>();
    final path = modelPath.toNativeUtf16();
    _P opts = nullptr;
    try {
      _check(_fn<IntPtr Function(_PP)>(10).asFunction<int Function(_PP)>()(out));
      opts = out.value;
      _check(_fn<IntPtr Function(_P, Int32)>(24)
          .asFunction<int Function(_P, int)>()(opts, threads));
      _check(_fn<IntPtr Function(_P, Int32)>(23)
          .asFunction<int Function(_P, int)>()(opts, 99)); // all optimizations
      _check(_fn<IntPtr Function(_P, Pointer<Utf16>, _P, _PP)>(7)
          .asFunction<int Function(_P, Pointer<Utf16>, _P, _PP)>()(
          _env, path, opts, out));
      final s = out.value;
      return OrtSession._(this, s, _name(s, 36), _name(s, 37));
    } finally {
      _release(100, opts);
      calloc.free(out);
      calloc.free(path);
    }
  }

  /// SessionGetInputName / SessionGetOutputName for index 0.
  Pointer<Utf8> _name(_P session, int fnIndex) {
    final out = calloc<Pointer<Utf8>>();
    try {
      _check(_fn<IntPtr Function(_P, IntPtr, _P, Pointer<Pointer<Utf8>>)>(fnIndex)
          .asFunction<int Function(_P, int, _P, Pointer<Pointer<Utf8>>)>()(
          session, 0, _alloc, out));
      // Copy: the original belongs to the runtime's allocator.
      final copy = out.value.toDartString().toNativeUtf8();
      _check(_fn<IntPtr Function(_P, _P)>(76)
          .asFunction<int Function(_P, _P)>()(_alloc, out.value.cast()));
      return copy;
    } finally {
      calloc.free(out);
    }
  }
}

/// A model with one float32 input and one float32 output.
class OrtSession {
  final Ort _ort;
  final _P _session;
  final Pointer<Utf8> _input, _output;
  OrtSession._(this._ort, this._session, this._input, this._output);

  OrtTensor run(Float32List data, List<int> shape) {
    final o = _ort;
    final buf = calloc<Float>(data.length);
    final dims = calloc<Int64>(shape.length);
    final out = calloc<Pointer<Void>>();
    final names = calloc<Pointer<Utf8>>(2);
    final values = calloc<Pointer<Void>>(2);
    _P input = nullptr, result = nullptr, info = nullptr;
    try {
      buf.asTypedList(data.length).setAll(0, data);
      for (var i = 0; i < shape.length; i++) {
        dims[i] = shape[i];
      }
      // CreateTensorWithDataAsOrtValue(mem, data, bytes, shape, rank, FLOAT = 1, out)
      o._check(o
          ._fn<IntPtr Function(_P, _P, IntPtr, Pointer<Int64>, IntPtr, Int32, _PP)>(49)
          .asFunction<int Function(_P, _P, int, Pointer<Int64>, int, int, _PP)>()(
          o._mem, buf.cast(), data.length * 4, dims, shape.length, 1, out));
      input = out.value;
      names[0] = _input;
      names[1] = _output;
      values[0] = input;
      values[1] = nullptr;
      // Run(session, options, inNames, inputs, 1, outNames, 1, outputs)
      o._check(o
          ._fn<IntPtr Function(_P, _P, Pointer<Pointer<Utf8>>, _PP, IntPtr,
              Pointer<Pointer<Utf8>>, IntPtr, _PP)>(9)
          .asFunction<int Function(_P, _P, Pointer<Pointer<Utf8>>, _PP, int,
              Pointer<Pointer<Utf8>>, int, _PP)>()(
          _session, nullptr, names, values, 1, names + 1, 1, values + 1));
      result = values[1];

      o._check(o._fn<IntPtr Function(_P, _PP)>(65)
          .asFunction<int Function(_P, _PP)>()(result, out));
      info = out.value;
      final rank = calloc<IntPtr>();
      o._check(o._fn<IntPtr Function(_P, Pointer<IntPtr>)>(61)
          .asFunction<int Function(_P, Pointer<IntPtr>)>()(info, rank));
      final n = rank.value;
      calloc.free(rank);
      final outDims = calloc<Int64>(n);
      o._check(o._fn<IntPtr Function(_P, Pointer<Int64>, IntPtr)>(62)
          .asFunction<int Function(_P, Pointer<Int64>, int)>()(info, outDims, n));
      final outShape = [for (var i = 0; i < n; i++) outDims[i]];
      calloc.free(outDims);
      final count = outShape.fold<int>(1, (a, b) => a * b);
      o._check(o._fn<IntPtr Function(_P, _PP)>(51)
          .asFunction<int Function(_P, _PP)>()(result, out));
      final copy = Float32List.fromList(out.value.cast<Float>().asTypedList(count));
      return OrtTensor(copy, outShape);
    } finally {
      o._release(99, info);
      o._release(96, result);
      o._release(96, input);
      calloc.free(buf);
      calloc.free(dims);
      calloc.free(out);
      calloc.free(names);
      calloc.free(values);
    }
  }

  void dispose() {
    _ort._release(95, _session);
    calloc.free(_input);
    calloc.free(_output);
  }
}
