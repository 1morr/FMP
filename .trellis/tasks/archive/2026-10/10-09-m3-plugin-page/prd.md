# 插件頁、設定頁的區塊、從檔案安裝（M3 PR 5）

> 父任務：`.trellis/tasks/10-08-m3-sources-accounts-devtools`。技術設計在父任務 `design.md` §6.7（設定頁的區塊順序）、§7.1（index 與讀取）、§7.3（啟用與停用）、§7.4（安裝、更新、移除的確認與閘門）、§7.5（插件頁）、§14（`file_picker`）；ADR 0014 §決定 6–8、ADR 0016 §決定 7（離線空狀態）、ADR 0024（設計系統）、ADR 0030、ADR 0009 §決定 6。執行清單在父任務 `implement.md`「5.」。本檔只列做什麼與驗收。

## 目標

使用者能在設定頁的「插件」區塊看到、安裝、更新、停用、移除插件，也能從檔案或網址安裝；資料與流程用 PR 4 的生命週期、PR 3 的官方 index。

## 做什麼

1. 平台層 `lib/platform/files/`：`file_picker` 13.x 的 `pickFiles` 選 `.js`；宣告 `PlatformCapabilities.files`。
2. 設定頁的區塊：外觀、播放、網路、插件（帳號在 PR 8、關於在 PR 11 才加，這個 PR 不顯示）；`SettingsGroup` 之外的區塊以同一個 list-detail 呈現（expanded 以上右側是區塊內容）。
3. 插件頁：
   - 已安裝／可安裝兩分頁（VS Code Extensions 的慣例）；
   - 已安裝：名稱、版本、作者、標記（開發中／已停用／沒有回應／有更新）、展開看能力與網域與來源、啟用開關、更新、移除；
   - 可安裝：官方與自訂 index 的插件，已裝的標「已安裝」；
   - 工具列：檢查更新、全部更新、從檔案安裝、從網址安裝、管理 index（列表、加入、刪除自訂 index）；
   - 安裝與更新的確認對話框（名稱、作者、版本、翻譯過的能力、網域、警告；從檔案或網址安裝加「非官方來源」；更新時能力或網域增加先列出新增部分）；移除確認。
4. 離線：可安裝分頁讀不到 index 時用共用的離線空狀態；已安裝分頁照常。
5. 三語言翻譯；文件（`app/AGENTS.md` 的 UI／平台層段落、ui 與 platform spec）。

## 不做

- 帳號區塊與「登入」按鈕（PR 8）；首次啟動引導（PR 6）；「關於」與 Debug 區塊（PR 11）；健康狀態（Debug 頁，ADR 0025）；`saveFile`、`getDirectoryPath`（PR 15、16）。

## 驗收

- [ ] widget 測試（design §7.5 的閘門）：兩分頁、標記、啟用開關寫入、安裝與更新確認（含「非官方來源」與新增能力或網域）、移除確認、離線空狀態；guideline 400／1000 寬。
- [ ] `platform_test.dart` 的 `files`；`install_search_play_test.dart` 若受影響照改。
- [ ] 驗證清單全綠（`app/AGENTS.md` § 驗證）。
- [ ] 實機（真實：`raw.githubusercontent.com`，插件請求最少），Android 模擬器與 Windows：插件頁看到官方插件 → 安裝（確認框列出能力與網域）→ 停用 B 站（搜尋 chip 消失）→ 再啟用 → 移除網易（資料庫裡帳號、storage、快取項目都不在）→ 從檔案安裝 `fmp-test`（「非官方來源」）。
- [ ] 更新流程實測（`fmp-plugins` 暫時分支 `test/m3-update-flow` 當自訂 index）：**push 暫時分支前先問擁有者**，驗完刪分支。
