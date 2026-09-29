# Windows 的 App 身分，依 flavor 決定（app/AGENTS.md § App 身分）。
#
# FLUTTER_APP_FLAVOR 由 flutter 工具寫進 flutter/ephemeral/generated_config.cmake
# （Flutter 3.47 起，https://docs.flutter.dev/deployment/flavors-windows）；
# pubspec.yaml 的 default-flavor 讓它永遠有值。prod 與舊版相同（ADR 0008
# §決定 3，舊版 windows/runner/main.cpp、Runner.rc），dev 每一項都不同（ADR 0015
# §決定 8）。test/identity/windows_identity_test.dart 以 `cmake -P` 執行本檔核對。
#
# - FMP_APP_USER_MODEL_ID：SetCurrentProcessExplicitAppUserModelID。
# - FMP_SINGLE_INSTANCE_NAME：單一實例 mutex 名稱，main.cpp 前面加 `Local\`。
# - FMP_DISPLAY_NAME：視窗標題與 FileDescription。第二個實例靠「視窗類別＋
#   標題」找第一個實例，所以兩個 flavor 的標題必須不同。
# - FMP_PRODUCT_NAME：Runner.rc 的 ProductName。path_provider 的 application
#   support 目錄是 %APPDATA%\<CompanyName>\<ProductName>，dev 靠它分開目錄。
if(FLUTTER_APP_FLAVOR STREQUAL "prod")
  set(FMP_APP_USER_MODEL_ID "com.personal.fmp")
  set(FMP_SINGLE_INSTANCE_NAME "FMP_MainInstance")
  set(FMP_DISPLAY_NAME "FMP")
  set(FMP_PRODUCT_NAME "fmp")
elseif(FLUTTER_APP_FLAVOR STREQUAL "dev")
  set(FMP_APP_USER_MODEL_ID "com.personal.fmp.dev")
  set(FMP_SINGLE_INSTANCE_NAME "FMP_MainInstance-dev")
  set(FMP_DISPLAY_NAME "FMP Dev")
  set(FMP_PRODUCT_NAME "fmp-dev")
else()
  message(FATAL_ERROR
    "Unknown FLUTTER_APP_FLAVOR '${FLUTTER_APP_FLAVOR}': expected dev or prod")
endif()
