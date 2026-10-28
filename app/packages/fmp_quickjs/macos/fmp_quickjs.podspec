# QuickJS 與 flutter_js 的 C 橋接（ADR 0036 §決定 1）。原始碼在套件根的 src/，Classes/ 裡是轉接檔。
# 編譯旗標照 android-js-runtimes 0.3.6 的 quickjs/CMakeLists.txt（Android 的 libfastdev_quickjs_runtime.so）。
Pod::Spec.new do |s|
  s.name             = 'fmp_quickjs'
  s.version          = '0.1.0'
  s.summary          = 'QuickJS and the flutter_js C bridge, linked into the FMP app.'
  s.homepage         = 'https://github.com/1morr/FMP'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'FMP' => 'https://github.com/1morr/FMP' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '12.0'
  s.library = 'c++'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) CONFIG_VERSION=\"2021-03-27\" QUICKJS=1',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    # 照搬的第三方原始碼，警告不是我們要修的，全關（-Wno-everything）。
    # 新的 clang 把 quickjs.c 兩處 `return NULL`（回傳整數的函式）當錯誤；Android 的 NDK 只是警告，行為不變。
    'OTHER_CFLAGS' => '$(inherited) -Wno-error=int-conversion -Wno-everything',
  }
  s.swift_version = '5.0'
end
