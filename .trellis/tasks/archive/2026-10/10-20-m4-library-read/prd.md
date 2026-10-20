# M4 PR 13：`libraryRead` 與帳號頁「歌單」

上層：`.trellis/tasks/10-15-m4-library-sync`（implement.md § 13、design §4.4、§4.7、§4.9、§7.3、§12、ADR 0032 §決定 3、6、7）。

## 目標

已登入的使用者在設定 → 帳號看到自己在該平台的歌單，勾選後一次匯入成 App 的匯入歌單。

## 需求

- **契約**（照 PR 6 `importPlaylist`、PR 20 `charts` 的做法）：
  - `LibraryReadExports`：`libraryPlaylists` 必要；`libraryLiveRooms` 選填，匯出了卻沒宣告 `live` 拒載（呼叫在 PR 15）。宣告 `libraryRead` 沒匯出 `libraryPlaylists`、匯出了沒宣告都拒載。
  - DTO：`LibraryPlaylistsQuery {cursor?}`、`LibraryPlaylistPage {playlists, cursor}`、`LibraryPlaylist {playlistId, title, artwork?, trackCount?, writable}`。`playlistId` 與 `title` 不空、同一頁 `playlistId` 不重複、`trackCount` 非負、`cursor` 空字串拒收。
  - `SourcePlugin.libraryPlaylists`；d.ts 同步（含 `libraryLiveRooms` 的宣告）。
  - `FmpChecks.libraryRead`：`FmpLibraryReadCheck` 必填 `requiresLogin: true`，跑 `libraryPlaylists` 第一頁。
- **重播帶假憑證**：`requiresLogin` 的非 `login` 案例在重播（契約測試、開發工具的重播模式）時，隔離環境放同一份 `checks.json` 裡 `login` 案例的 `input`（假憑證）；沒有 `login` 案例就不放。真實的已存憑證永遠不進重播。
- **健康檢查**：`requiresLogin` 的非 `login` 案例已登入時跑、未登入略過（PR 12 留下沒有測試的那條）。
- **帳號頁**：卡片在 `CredentialState.active` 且插件宣告 `libraryRead` 時多一顆「歌單」，開一頁（設定分頁自己的導覽堆疊內）：
  - 讀完所有頁（超過 20 頁停下、顯示已讀的並記 warning）；載入中、失敗（可重試、離線字樣）、空清單各有狀態。
  - 每列：封面、名稱、首數、「可寫」標記；已匯入（`playlist_remote` 同插件同 id）標「已匯入」並停用勾選。
  - 「匯入所選」：逐張經 `PlaylistImporter`（以插件與 `playlistId`，不經網址），進度「n／總數」；失敗的那列標出錯誤、其他照做；完成提示「已匯入 n 張」，有失敗附「k 張失敗」。
- **`fmp-test`**：宣告 `libraryRead`；登入後 `libraryPlaylists` 回 `pl-auth`（可寫）與 `pl-basic`（不可寫），未登入 `AuthRequired`；`checks.json` 加 `libraryRead` 案例；README 更新。
- **文件**：`app/AGENTS.md` § 插件、`.trellis/spec/app/plugins/index.md` 的對應段落。

## 驗收

- [x] `library_read_capability_test.dart`：匯出與能力的四種拒載、回傳值驗證、`requiresLogin` 案例形狀；`type_definitions_test.dart` 一致。
- [x] 契約與開發工具重播：`fmp-test` 的 `libraryRead` 案例以 `login` 案例的假憑證通過；拿掉注入會紅（雙向變異）；重播不帶真實憑證的既有閘門仍在。
- [x] 健康檢查：已登入跑、未登入略過，各有測試。
- [x] 帳號頁 widget 測試：只在已登入且宣告時出現、已匯入停用勾選、部分失敗列出。
- [x] `toast_layering_test.dart` 加新頁。
- [x] 實機：Android 重播（`fmp-test` 登入 → 歌單 → 匯入 `pl-auth`）。
- [x] 實機真實（擁有者登入，Windows）：三平台各列出一次、匯入「FMP 測試」一次、關掉「以登入身分瀏覽與播放」後刷新一次、恢復；以 App 內工具錄 `libraryRead` 案例並刪減。

## 不做

- `libraryLiveRooms` 的呼叫與 UI（PR 15）、`libraryWrite`（PR 14）。
- 在帳號頁「在遠端新增歌單」（design §7.3）。

## 與計畫不同之處

- 真實實測與錄製都在 Windows 做（計畫寫真實在 Android、錄製在 Windows）：錄製工具只在桌面，三個平台在同一台登入一次就好，PR 14、15 沿用。Android 以重播驗 UI。
- 帳號頁匯入時把 `libraryPlaylists` 的 `writable` 帶進 `playlist_remote`（`importPlaylistId(writable:)`）：網易、YouTube 的 `importPlaylist` 不給 `writable`，實測時自己的「FMP 測試」匯入後是 0。
