# Linux 平台任務

2026-10-01 擁有者決定：Mac 到貨後與 macOS、iOS 一起在 Mac 上做，M2 先行（ADR 0026 §決定 4 的修訂）。**尚未規劃**：開工時先走 brainstorm，
本檔只記已知的範圍與從 M1 帶過來的線索。

## 已知範圍

- 讓 Linux 從「此平台尚未支援」變成能用：平台層宣告與實作資料目錄、字型 fallback、播放（ADR 0009 §決定 4、7）。
- 播放後端：`media_kit`（libmpv），需加入 Linux 的原生庫或改用系統 libmpv（`app/lib/platform/audio/audio.dart` 已註明「之後 Linux」）。
- 單一實例（`phase2-plan.md` 的「§8 平台功能」決定：單一實例開到所有桌面平台）。
- 驗收環境在 Mac 上，X11 與 Wayland 各一次；虛擬機與做法在本任務決定。留意 Apple Silicon 上的虛擬機是 arm64，而發佈物是 `linux-x86_64.AppImage`（ADR 0022 §決定 3）。
- 之後每個里程碑在虛擬機跑一次冒煙測試。
- 延後實測（`phase2-plan.md` §8）：
  - 沒有 keyring 時的 secure storage（ADR 0012）；
  - X11／Wayland 桌面歌詞（ADR 0021，M7 之後才有東西可測）；
  - AppImage 的改名替換（ADR 0022）。

## 從 M1 帶過來的線索

- CI 已有 Linux 的 prod release 建置與 xvfb 下的整合測試（#192）。
- `app/linux/CMakeLists.txt` 補了 flutter_js 0.8.7 漏裝的 QuickJS 原生庫；升 flutter_js 時重看。
- Linux 的 `flutter test` 可直接載入 QuickJS（`test/support/quickjs.dart`）。
- 發版目前只有 Android、Windows；`fmp-v{版本}-linux-x86_64.AppImage` 由本任務加入 `app-release.yml`（ADR 0022 §決定 3）。

## 驗收

開工規劃時定。
