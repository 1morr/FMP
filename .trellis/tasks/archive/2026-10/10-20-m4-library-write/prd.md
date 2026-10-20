# M4 PR 14：`libraryWrite` 與遠端操作

上層：`.trellis/tasks/10-15-m4-library-sync`（implement.md § 14、design §4.5、§4.7、§4.9、§7.1、§7.2、§10.6、§10.7、ADR 0032 §決定 4、6、7、ADR 0019 §決定 4）。

## 目標

已登入的使用者可以把曲目加入自己在平台上的歌單（含在遠端新增一張），也可以從匯入的可寫歌單把曲目移出遠端；本地副本跟著更新。

## 需求

- **契約**：`LibraryWriteExports`（`createPlaylist`、`addToPlaylist`、`removeFromPlaylist` 三個都必要）；宣告 `libraryWrite` 沒宣告 `libraryRead` 是 `Unsupported`（manifest 驗證）；`results` 與輸入不同長是 `ParseError`；`status` union 與 `error` 的結構化錯誤經 `plugin_runtime` 的同一個轉換成 `AppError`。`SourcePlugin` 三個方法、d.ts、`FmpChecks.libraryWrite`（必填 `requiresLogin: true` 與 `mutates: true`，跑 `addToPlaylist`）。
- **入口**（design §7.1、§7.2、§10.6、§10.7）：
  - 「加入遠端歌單…」：曲目選單與多選；條件是曲目所屬插件宣告 `libraryWrite`、已啟用、`CredentialState.active`；多選時全部屬於同一個這樣的插件，否則停用並說明。
  - 「從遠端歌單移除」：匯入歌單詳情的曲目選單與多選；條件是 `playlist_remote.writable`、插件宣告 `libraryWrite`、已登入。
- **加入對話框**：開啟時讀完 `libraryPlaylists`，只列 `writable` 的、勾選框；「在遠端新增歌單」輸入名稱 → `createPlaylist` → 出現在清單並已勾選；「加入」直接送出（不另確認），每個勾選的歌單一次 `addToPlaylist`。提示「已加入 n 個歌單」，附「m 首已存在」「k 項失敗」與「詳細」。
- **移除**：確認框列出首數 → `removeFromPlaylist`（`sourceId`、`cid`、`remoteItemId`）→ `removed`／`notPresent` 從本地刪 → 背景刷新一次 → `failed` 提示並列出。
- **寫後刷新**：加入成功的目標若在 `playlist_remote`（同插件同 `remote_id`）排一次刷新；與手動、排程刷新共用同一個互斥（一次只刷一張）。
- **`fmp-test`**：`libraryWrite` 假實作（design §4.9）；`checks.json` 的 `libraryWrite` 案例（`mutates`）；README。
- **健康檢查**：三個官方插件的 `libraryWrite` 顯示「略過：會改動遠端」。

## 驗收

- [x] `library_write_capability_test.dart`；入口條件；結果提示三種；移除確認框、刪本地、`failed` 列出；寫後刷新進同一個互斥；`mutates` 案例在健康檢查略過。
- [x] 實機重播（Android）：`fmp-test` 登入 → 加入 `pl-auth`（`added`）→ 再加一次（`alreadyPresent`）→ 加 `fail`（`failed`）→ 在遠端新增歌單 → 匯入的 `pl-auth` 詳情「從遠端歌單移除」。
- [x] 實機真實（擁有者在場，Windows）：三個平台各在「FMP 測試」加入一首、移除同一首各一次；網易先不帶 `X-Real-IP`。不做真實的「在遠端新增歌單」。
- [x] Debug 頁健康檢查：三個插件的 `libraryWrite` 顯示「略過：會改動遠端」。

## 不做

- 真實的「在遠端新增歌單」（決定 4，只以 `fmp-test` 重播驗）。
- 以網址匯入的自己的歌單的 `writable`（PR 13 的後續，入口仍看 `playlist_remote.writable`）。

## 與計畫不同之處

- 真實實測在 Windows（沿用 PR 13 的登入）。
- 寫後刷新延後 60 秒：YouTube 寫後讀有延遲（實測約 40 秒）。本地刪除仍立即。
- 健康檢查的「略過」由測試守，實機沒看（開發入口裝的插件沒有 `checks.json`）。
