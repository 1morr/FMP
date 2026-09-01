# FMP 建置指南

本文件說明如何在本機建置 FMP（Flutter Music Player）的 Android APK 和 Windows 安裝包。

本文件只涵蓋本機建置。CI 發布流程、簽名 Secrets、Release 產物命名與應用內更新資產規則見〈[建置與發布指南](build-and-release.md)〉。

## 前置條件

| 工具 | 版本要求 | 用途 |
|------|---------|------|
| [Flutter SDK](https://flutter.dev/docs/get-started/install) | >= 3.5.0 | 跨平臺框架 |
| [Java JDK](https://adoptium.net/) | 17 | Android 建置（同時提供 `keytool` 指令） |

### Windows 本機建置額外要求

`flutter doctor` 只檢查 Flutter、Visual Studio、Windows SDK 等基礎環境。本專案的部分 Windows 外掛還會在 CMake/MSBuild 階段建置或下載原生依賴，因此 Windows 本機建置還需要以下工具在 PATH 中可用：

| 工具 | 用途 | 缺失時常見錯誤 |
|------|------|---------------|
| [NuGet CLI](https://www.nuget.org/downloads) | `flutter_inappwebview_windows` 下載 WebView2、WIL、nlohmann.json 等 NuGet 原生依賴 | `Nuget is not installed`、`NUGET-NOTFOUND install ...` |
| [Rust 工具鏈](https://www.rust-lang.org/tools/install) | `smtc_windows` 透過 cargokit 編譯 Rust 原生函式庫 | `cargo` / `rustc` not recognized，或 `smtc_windows_cargokit` 建置失敗 |

推薦用 winget 安裝：

```powershell
winget install -e --id Microsoft.NuGet
winget install -e --id Rustlang.Rustup
```

安裝後重啟終端機或 VS Code，讓 PATH 更新生效，然後確認指令可用：

```powershell
nuget help
cargo --version
rustc --version
```

> 如果剛安裝後目前終端機仍找不到指令，通常是 PATH 尚未重新整理。NuGet 的 winget alias 常見位置為 `%LOCALAPPDATA%\Microsoft\WinGet\Links`，Rust 工具鏈常見位置為 `%USERPROFILE%\.cargo\bin`。

## 初始化專案

```bash
git clone <repo-url>
cd FMP

# 安裝依賴
flutter pub get

# 程式碼產生（Isar models、i18n 等）
dart run build_runner build --delete-conflicting-outputs

# 產生應用程式圖示
dart run flutter_launcher_icons
```

## 建置 Android APK

```bash
flutter build apk --release
```

產物路徑：`build/app/outputs/flutter-apk/app-release.apk`

### 簽名金鑰（可選）

不設定簽名金鑰也能建置，APK 會使用 debug 簽名。唯一的影響是：**不同簽名的 APK 無法覆蓋安裝**（系統會顯示 "package conflicts"），需要先解除安裝舊版本。

如果需要固定簽名（讓安裝更新時不必先解除安裝），到〈[建置與發布指南 §1](build-and-release.md#1-android-簽名配置)〉產生 Keystore 並建立 `android/key.properties`——本機建置與 CI 共用同一套簽名程序，這裡不重複列出步驟。

## 建置 Windows

建置前建議先確認 Windows 原生工具鏈已可用：

```powershell
flutter doctor -v
nuget help
cargo --version
rustc --version
```

### 只建置 EXE（免安裝版）

```bash
flutter build windows --release
```

產物目錄：`build\windows\x64\runner\Release\`

可以直接執行 `fmp.exe`，但 Windows SMTC（系統媒體傳輸控制項）不會正確顯示應用程式圖示和名稱。需要透過安裝包安裝才能完整支援 SMTC。

### 建置安裝包

安裝包使用 [Inno Setup](https://jrsoftware.org/isinfo.php) 產生 `.exe` 安裝程式。安裝後會建立帶有 `AppUserModelID` 的開始功能表和桌面捷徑，讓 SMTC 能正確識別應用程式。

#### 前置條件

安裝 Inno Setup（只有建置安裝包時需要）：

```bash
winget install -e --id JRSoftware.InnoSetup
```

#### 運作原理

專案使用 [`inno_bundle`](https://pub.dev/packages/inno_bundle) Dart 套件（已設定在 `dev_dependencies` 中）自動產生 Inno Setup 指令碼。它讀取 `pubspec.yaml` 中的 `inno_bundle` 設定區塊，掃描 Flutter 建置產物目錄，產生一個 `.iss` 指令碼檔案，再呼叫 Inno Setup 的命令列編譯器 `ISCC.exe` 將其編譯為安裝包。

流程：`pubspec.yaml 設定` → `inno_bundle 產生 .iss 指令碼` → `ISCC.exe 編譯為 .exe 安裝包`

#### 方法一：一鍵建置

```bash
dart run inno_bundle:build --release
```

這個指令會依序執行：建置 Flutter → 產生 ISS 指令碼 → 呼叫 ISCC.exe 編譯安裝包。

#### 方法二：分步建置

`inno_bundle` 呼叫 `ISCC.exe` 時可能因路徑含空格而失敗，此時可以分步操作：

```bash
# 1. 建置 Flutter（如果已建置可跳過）
flutter build windows --release

# 2. 只產生 ISS 指令碼（--no-app 跳過 Flutter 建置，--no-installer 跳過 ISCC 編譯）
dart run inno_bundle:build --release --no-app --no-installer

# 3. 手動呼叫 ISCC.exe 編譯 ISS 指令碼
& "C:\Users\<使用者名稱>\AppData\Local\Programs\Inno Setup 6\ISCC.exe" build\windows\x64\installer\Release\inno-script.iss
```

產物路徑：`build\windows\x64\installer\Release\FMP-x86_64-<版本>-Installer.exe`

### SMTC 與 AppUserModelID

安裝包捷徑會帶上 `AppUserModelID`，讓 Windows SMTC 能正確識別應用程式身分；`inno_bundle` 預設不會產生這個屬性，CI 建置時會自動修補指令碼。完整原理（行程層級設定、`windows/runner/main.cpp` 的 `SetCurrentProcessExplicitAppUserModelID` 呼叫，以及為何兩者必須一致）見〈[建置與發布指南 §3](build-and-release.md#3-windows-安裝包-innosetup)〉。

### 安裝包設定

設定位於 `pubspec.yaml` 的 `inno_bundle` 區塊：

```yaml
inno_bundle:
  id: BAF6CE8D-E1C8-4C29-AE0B-EDE98D5F8FAA  # AppId，發布後不可更改
  name: FMP
  description: "Flutter Music Player - 跨平台音乐播放器"
  publisher: FMP
  installer_icon: windows/runner/resources/app_icon.ico
  admin: false  # 不需要系統管理員權限安裝
```

> **重要**：`id` 是 GUID 格式的 AppId，**發布後不可更改**。更改會導致使用者機器將更新視為不同的應用程式。

## 常用指令

```bash
# 執行（除錯模式）
flutter run

# 指定 Windows 桌面端執行
flutter run -d windows

# 靜態分析
flutter analyze

# 執行測試
flutter test

# 重新產生程式碼（修改 Isar model 後必須執行）
dart run build_runner build --delete-conflicting-outputs
```

## Windows 建置排錯

### `flutter doctor` 沒有錯誤，但 `flutter run -d windows` 仍然失敗

先看錯誤發生在哪一層：

- `NUGET-NOTFOUND` / `Nuget is not installed`：安裝 NuGet CLI，並重啟終端機。
- `smtc_windows_cargokit` 失敗，或提示找不到 `cargo` / `rustc`：安裝 Rustup/Rust 工具鏈，並重啟終端機。
- `Error waiting for a debug connection`：確認沒有舊的 `fmp.exe` 正在執行。舊行程可能佔用除錯連線或讓 Flutter runner 誤判啟動狀態。

建置成功時可以忽略的無害警告（例如 `resolve_symlinks.ps1` 的 `Get-Item ... AppData` 訊息）見〈[疑難排解](troubleshooting.md#建置時的無害雜訊)〉。

可以用以下指令檢查並結束舊行程：

```powershell
Get-Process -Name fmp -ErrorAction SilentlyContinue
Stop-Process -Name fmp -ErrorAction SilentlyContinue
```

安裝新工具或清除舊建置狀態後，建議重建一次：

```powershell
flutter clean
flutter pub get
flutter run -d windows
```

## 相關檔案

| 檔案 | 說明 |
|------|------|
| `pubspec.yaml` | 依賴和安裝包設定 |
| `windows/runner/main.cpp` | Windows 進入點，`SetCurrentProcessExplicitAppUserModelID` |
| `windows/runner/resources/app_icon.ico` | 應用程式和安裝包圖示 |
| `android/app/build.gradle.kts` | Android 簽名和建置設定 |

---

## 更多資源

- [文件地圖](README.md)
- [建置與發布指南](build-and-release.md) - CI、Release、簽名 Secrets、更新資產
- [返回 README](../README.md)
- [開發文件](development.md) - 專案架構、技術棧、開發規範
