# 0006 — Release 驗過產物就直接發布，不再留草稿等人按

- 狀態：已決定、尚未實作
- 日期：2026-09-24
- 影響範圍：`.github/workflows/release.yml`、`test/workflows/release_workflow_test.dart`、`docs/build-and-release.md` 的發布流程

## 背景

`release.yml` 的 job 鏈是 `prepare → validate → build-android（4 個 ABI）+
build-windows → release`。`prepare` 檢查 tag 是 `vMAJOR.MINOR.PATCH` 且存在，並算出
`version_code = major * 1000000 + minor * 1000 + patch`；兩個 build job 都先把
`pubspec.yaml` 的 `version:` 改寫成 tag 的版本再建置（`android/app/build.gradle.kts`
的 `versionName` / `versionCode` 取自 `flutter.versionName` / `flutter.versionCode`）。
最後的 `release` job 以 `softprops/action-gh-release` 建 Release，帶
`draft: true`，`test/workflows/release_workflow_test.dart` 以字串斷言釘住這一行。

草稿是 `9adc95a5`（2026-09-09）加的。commit message 的理由是：調查的五個專案
有四個先建草稿再由人發布；v1.10.0 的 release notes 宣傳了一個隔天就被撤回的
改動，沒有人有機會先讀。草稿對外不可見：README 的
`releases/latest/download/...` 連結看不到它，`update_service.dart` 查的 GitHub API
`releases/latest` 依官方文件也只回傳「non-prerelease, non-draft」的版本。

目前一個 Release 有 10 個 asset（`v1.10.2` 實際就是這 10 個，2026-09-24 以
`gh release view` 查證）：

- 4 個版本化 APK：`fmp-<tag>-android-{arm64-v8a,armeabi-v7a,x86_64,universal}.apk`
- 3 個穩定別名：`fmp-latest-android-universal.apk`、`fmp-latest-windows.zip`、
  `fmp-latest-windows-installer.exe`
- `fmp-<tag>-windows.zip`、`fmp-<tag>-windows-installer.exe`
- `fmp-<tag>-checksums.sha256`：只涵蓋 7 個版本化檔案，刻意排除 `fmp-latest-*`

App 內更新讀的正是這份 checksums（`update_service.dart` 找
`-checksums.sha256` 結尾的 asset）與 Release body（`data['body']` 成為更新對話框
的 `releaseNotes`）。

## 決策

**擁有者的決定：不要人工按 publish。** `release` job 改成 `draft: false`，並
`needs` 一個新的驗證 job。人工那一步是整條流程唯一的人為閘門，而它沒有定義要
檢查什麼；能自動檢查的，交給 job。驗證 job 檢查：

1. **asset 齊全**：上面 10 個檔名一個不少。將來加別名（例如 arm64 的
   `fmp-latest-*`）時，這份清單與數字要一起改。
2. **checksums 與產物一致**：manifest 每一行的 hash 與對應的版本化檔案相符，
   7 個版本化檔案都在 manifest 裡。
3. **APK 版本對得上 tag**：`versionName` 等於 tag 去掉 `v`，`versionCode` 等於
   `prepare` 算出來的值。今天這靠建置時的 pubspec 改寫成立；倉庫裡的 pubspec
   與 tag 不一致確實發生過（`v1.10.0` 這個 tag 上的 `pubspec.yaml` 是
   `1.9.1+1009001`），這項檢查守的是那一步改寫不會悄悄失效。
4. **Windows installer 是真的安裝檔**：非 0 位元組，且能被辨識為執行檔。

`release_workflow_test.dart` 同步改寫：不再釘 `draft: true`，改釘「驗證 job 存在，
且 `release` job 的 `needs` 包含它」。撤掉草稿的那個 commit 要寫明接手的是這四項
檢查。

## 被否決的替代方案

### 維持草稿 + 人工 publish

- 草稿之前的所有檢查（tag 格式、analyze、test、ISS patch 驗證、各 build job）
  不論有沒有草稿都照跑。撤掉草稿不會少掉任何一項既有檢查，保留它也不會多一項。
- 人工那一步沒有清單。`release.yml` 的註解寫「artifacts are unverified until
  someone looks」，`docs/build-and-release.md` 寫「這一步是給人看 body 與產物的
  機會」，但沒有一處說要看什麼。上面四項驗證比「有人看過」具體。
- 擁有者不想要這個手動步驟。

### 保留草稿，另加「草稿放太久」的提醒

針對的是「忘了按」，但手動步驟還在，與擁有者的決定相反。

## 後果

- **Release body 不再有人先讀。** `9adc95a5` 加草稿的具體理由是 v1.10.0 的
  notes，而驗證 job 不看 body。body 是從 commit 範圍依 Conventional Commits 前綴
  自動分組產生的，發布後直接成為 App 內更新對話框的內容。這是知情接受的取捨。
- **驗證通過就立刻對外**：README 的穩定連結與 App 內更新同時指向新版。驗證 job
  只擋結構性錯誤（缺檔、hash 不符、版本錯、壞的安裝檔），不擋執行期的壞 build。
- 實作時 `docs/build-and-release.md` 的「發布流程」一節要一起改，它現在描述的是
  草稿流程。
- 實作之前，`draft: true` 與釘住它的測試照舊有效。
