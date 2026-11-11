// 實驗用（可丟棄）：讀行程累計 CPU 時間，用來確認中斷後 JS 迴圈真的停了、
// 不是只有 Dart 端的 Future 先回來而原生執行緒還在空轉。
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

typedef _GetRusageC = Int32 Function(Int32 who, Pointer<Uint8> usage);
typedef _GetRusage = int Function(int who, Pointer<Uint8> usage);
typedef _GetCurrentProcessC = IntPtr Function();
typedef _GetCurrentProcess = int Function();
typedef _GetProcessTimesC = Int32 Function(
  IntPtr h,
  Pointer<Uint64> c,
  Pointer<Uint64> e,
  Pointer<Uint64> k,
  Pointer<Uint64> u,
);
typedef _GetProcessTimes = int Function(
  int h,
  Pointer<Uint64> c,
  Pointer<Uint64> e,
  Pointer<Uint64> k,
  Pointer<Uint64> u,
);

/// 行程到目前為止用掉的 user + system CPU 毫秒（所有執行緒加總）。
int processCpuMs() {
  if (Platform.isWindows) {
    final k32 = DynamicLibrary.open('kernel32.dll');
    final current = k32.lookupFunction<_GetCurrentProcessC, _GetCurrentProcess>(
      'GetCurrentProcess',
    );
    final times = k32.lookupFunction<_GetProcessTimesC, _GetProcessTimes>(
      'GetProcessTimes',
    );
    final buf = calloc<Uint64>(4);
    try {
      if (times(current(), buf, buf + 1, buf + 2, buf + 3) == 0)
        throw StateError('GetProcessTimes failed');
      return (buf[2] + buf[3]) ~/ 10000; // FILETIME 是 100 ns
    } finally {
      calloc.free(buf);
    }
  }
  final getrusage = DynamicLibrary.process()
      .lookupFunction<_GetRusageC, _GetRusage>('getrusage');
  final buf = calloc<Uint8>(256);
  try {
    if (getrusage(0 /* RUSAGE_SELF */, buf) != 0)
      throw StateError('getrusage failed');
    final d = buf.cast<Uint8>().asTypedList(256).buffer.asByteData();
    // struct rusage 開頭兩個 timeval（64 位元的 Darwin 與 Linux 都是 16 bytes）；
    // tv_usec 在 Darwin 是 int32、Linux 是 long，小端序取低 32 位元兩邊都對。
    int ms(int off) =>
        d.getInt64(off, Endian.little) * 1000 +
        d.getInt32(off + 8, Endian.little) ~/ 1000;
    return ms(0) + ms(16);
  } finally {
    calloc.free(buf);
  }
}

/// 等 [window]，回傳這段時間行程用掉的 CPU 毫秒。迴圈還在空轉的話接近 window（或更多）。
Future<int> cpuMsDuring(Duration window) async {
  final before = processCpuMs();
  await Future<void>.delayed(window);
  return processCpuMs() - before;
}
