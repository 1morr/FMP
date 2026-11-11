// FMP 補的符號：flutter_js 0.8.7 的 lib/quickjs/ffi.dart 會查 jsSetMemoryLimit，
// android-js-runtimes 0.3.6 的橋接沒有它（Android 的 .so 也沒有，lookup 是延遲的，
// 只有設了 memoryLimit 才會用到）。補上讓符號清單完整，行為同 QuickJS 的 JS_SetMemoryLimit。
#include <stddef.h>
#include "quickjs/quickjs.h"

#if defined(_MSC_VER)
#define FMP_EXPORT __declspec(dllexport)
#else
#define FMP_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

FMP_EXPORT void jsSetMemoryLimit(JSRuntime *rt, size_t limit) {
  JS_SetMemoryLimit(rt, limit);
}
