# 0014 — 音源是執行期 JS 腳本插件，App 不內建，從插件庫安裝

- 狀態：已採納
- 日期：2026-09-27
- 影響範圍：`SourcePlugin` 介面與註冊表、JS 執行環境與宿主 API、插件頁與首次啟動引導、legacy import 的升級提示、
  新 repo `1morr/fmp-plugins`、匹配流程

## 背景

舊專案已有小介面（`SourceCapability` 系列），但新增一個能搜能播的音源最少要改 15 個檔、同網易程度約 54 個；
50 處音源分支散在 28 個檔；電台、Mix、遠端歌單寫死特定音源；歌單匯入與歌詞各有一套匹配評分
（`docs/audit/sources.md`）。

擁有者要求：單一註冊點宣告能力、UI 依能力出現入口、UI 與 service 沒有音源分支、統一匹配流程；
並希望使用者能以 AI Agent 生成自己的音源並安裝。FMP 不上架任何商店（ADR 0009）。
為此，擁有者明確將腳本插件納入重寫範圍（功能凍結的例外）。

ADR 0009–0013 已定的音源義務（遮蔽名單、`AuthRequirement`、登入方式、憑證無效判定、錯誤對應表、重試策略）由插件的
manifest 與腳本承擔。

## 考慮過的選項

- **編譯期 Dart 插件**：型別與測試最直接；但修音源要發 App 新版，使用者無法自行加音源。否決。
- **先用 Dart 寫內建音源、之後再轉腳本**：前期穩，但三個音源邏輯要寫兩次，腳本 API 很晚才被真實使用驗證。否決。
- **腳本語言用 `hetu_script`**（Spotube 採用）：Dart 風格小眾語言，AI 生成能力差。否決，改用 JS。
- **內建腳本隨 App 打包**：首次啟動即可用；但修音源仍要發 App、App 本體含非官方 API 呼叫。否決。
- **插件放在 FMP 主 repo**：CI 與版本管理簡單，但失去 App 本體與插件的分離。否決。
- **背景自動檢查插件更新**：與擁有者對 App 更新「只手動檢查」的要求不一致。否決。
- **允許腳本讀其他音源憑證或檔案系統**：否決。

## 決定

1. **一套介面 `SourcePlugin`**：App 其他部分只認介面與能力宣告，分不出來源是誰、是否為腳本；UI 與 service 沒有針對特定音源的分支。
2. **所有來源都是 JS 腳本＋manifest，App 不內建任何來源**：可播放音源（B 站、網易、YouTube）、僅元資料來源（Spotify、QQ 匯入）、
   歌詞源（網易、QQ、lrclib）。引擎為 `flutter_js`（Android／Windows／Linux 用 QuickJS，iOS／macOS 用 JavaScriptCore），ES2020。
   音源邏輯以舊 Dart 程式碼為規格、用 JS 重寫（調整 ADR 0008 的「搬運葉節點」僅適用非音源部分）。
3. **manifest**：`id`（字串音源 id）、名稱、版本、作者、`apiVersion`、能力、允許的網域、登入方式、重試與限流策略、遮蔽名單追加、預設值、圖示。
4. **能力**：`search`、`resolveStream`、`trackDetail`、`multiPart`、`importPlaylist`、`libraryRead`、`libraryWrite`、`charts`、`live`、`mix`、`lyrics`、`login`。
   可播放音源＝有 `resolveStream`；僅元資料來源與歌詞源依能力區分，不另立型別。下載由宿主處理，不是插件能力。
   同一能力有多個提供者時 UI 全部列出。`lyrics` 的介面與歌詞文件格式、新增的 AI 能力 `aiAssist` 見 ADR 0021。
5. **宿主 API v1**（腳本能用的全部）：`http.request`（經 ADR 0012／0013 網路層、只能連 manifest 網域）、`crypto`、每插件 `storage`、
   只讀自己音源的 `credentials`、`log`（經 ADR 0011 門面）、結構化錯誤（宿主轉成 `AppError`）。沒有檔案系統、任意 socket、其他插件的資料。
   資料交換為以 `apiVersion` 版本化的 JSON DTO，宿主提供 TypeScript 型別定義。`resolveStream` 回傳網址期限 `expiresAt`（插件從網址本身讀），
   封面為多尺寸清單 `artwork`（ADR 0016）。
   `resolveStream` 的輸入含平台可播格式與用途（播放／下載，ADR 0020）、輸出為依優先序排好的候選串流；`live` 提供直播串流與直播狀態（ADR 0018）。
   補充（2026-10-06，M2 PR 12）：`resolveStream` 的輸出可另標選填的 `previewOnly`（候選只有試聽片段，宿主依「跳過試聽片段」處理，ADR 0018 §決定 7）；宿主 API 發佈前在 v1 內擴充，`apiVersion` 不變。
6. **插件庫**：官方插件在獨立 repo `1morr/fmp-plugins`，每插件一目錄（腳本、manifest、錄下的測試 fixture），其 CI 跑契約測試並產生
   `index.json`（含 SHA-256）。App 插件頁預設讀官方 index，可加自訂 index 網址，也可從檔案或網址安裝；由 index 安裝時驗證 SHA-256。
   安裝前顯示能力與會連的網域，並警告「此腳本會以你的登入身分存取這些網站」。
7. **更新**：只在打開插件頁或手動檢查時比對 index，可一鍵全部更新；音源壞掉以更新插件修復，不必發 App 新版。
8. **首次啟動與升級**：沒有來源時引導安裝官方插件；legacy import 偵測舊資料用到的音源並提示一鍵安裝，未安裝前曲目標示「音源未安裝」。
   移除插件時清除其 storage 與憑證，曲目保留並標示。
9. **匹配**：宿主一份共用評分核心（標題、歌手、時長容差，歌詞另加同步歌詞加分），歌單匯入與歌詞共用；對所有啟用的目標來源比較取最高分，
   同分依使用者排序；目標來源集合由使用者設定，自動與手動重搜一致；結果持久化，使用者改選後不再重算；匹配失敗保留並標示。
   評分核心的正規化、相似度與套件見 ADR 0019。
10. **YouTube 退路**：可行性驗證（YouTube.js 在 `flutter_js` 能否搜尋並解出串流；它官方只寫支援 Node.js、Deno、瀏覽器，需宿主提供 fetch 與 eval）
    有時限；失敗則 YouTube 暫以 Dart 實作同一個 `SourcePlugin` 介面。
   補充（2026-09-30，M1 探針）：驗證通過。YouTube.js 18.1.0 以 esbuild 打成單一插件檔（793 KB，約 204 KB gzip），fetch／URL／TextEncoder 等 Web API 在插件檔內以 `fmp.http.request` 為底補上，不改宿主 API v1；Android 與 Windows 都能搜尋，並以 VISIONOS client 解出不需登入、不需 PO token 的完整音訊網址，由 just_audio／media_kit 播出（Android 只驗到音訊系統層）。可用的 client 會隨 YouTube 封鎖而換（ANDROID_VR 自 2026-08-26 起只給約 60 秒），插件不必發新版 App 就能跟上，所以 M3 的 YouTube 走插件、不改用 Dart。證據在 `.trellis/tasks/archive/2026-09/09-30-youtubejs-probe/research/youtubejs-probe.md`。

採用的慣例：MusicFree、LX Music 的 JS 腳本插件與插件訂閱（App 本體不附音源）；Spotube 的 manifest（能力、API 版本）與 iOS 側載發佈；
Flutter federated plugin 的「一套介面、多種實作」；Spotube 的匹配結果快取與使用者改選。只參考設計，不複製程式碼（MusicFree 為 AGPL-3.0）。

補充（2026-09-30，M1）：從檔案或網址安裝的單位是**單一 `.js` 檔**，開頭以 `/* ==FMP Plugin==` 與 `==/FMP Plugin== */` 包一段 JSON manifest；宿主不執行腳本即可讀出 manifest，先檢查網域與能力再載入（使用者腳本 metadata block 的慣例）。index 的 SHA-256 針對這個檔。擁有者 2026-09-30 選定。

補充（2026-09-30，M1）：每個插件的 JS 執行環境在自己的背景 isolate 執行。`flutter_js` 0.8.7 的 QuickJS 沒有中斷機制，同步無窮迴圈會卡住所在的執行緒；放在背景 isolate 後 UI 不受影響。呼叫逾時時宿主先送存活探測：有回應代表只是在等網路，這次呼叫以 `NetworkError` 失敗、插件照常；沒有回應或 isolate 已結束，插件標為「沒有回應」並停用到 App 重啟（卡住的執行緒無法回收）。宿主 API 的安全檢查仍在主 isolate。擁有者 2026-09-30 選定；可中斷的替代套件（`flutter_qjs_next`、`quickjs_engine`）因單一作者、低採用而未採用。

## 後果

- 好的：新增音源＝在插件庫新增一個目錄或自行安裝腳本；修音源不必發 App；ADR 0011–0013 的保護自動套用到所有腳本；
  App 本體不含非官方 API 呼叫，降低主 repo 的暴露面（不消除風險；B 站社群 API 文件庫已於 2026-01 因存證信函關閉）。
- 壞的：第一個里程碑變重（要先有 JS 執行環境與宿主 API）；腳本除錯比 Dart 難；首次啟動多一步安裝；要維護第二個 repo 與其 CI；
  宿主 API 一經發佈就要維持相容（以 `apiVersion` 管理）。
- 之後要注意：`flutter_js` 在 Android 與 Windows 的 Promise、記憶體與啟動成本需實測；YouTube 可行性驗證；插件庫 repo 與插件頁在 M3 建立（ADR 0026）；
  自動檢查插件更新若日後需要，另立決定。

## 如何確認

- 結構測試：每個插件的 manifest 能力與它實際匯出的函式一致；`apiVersion` 不相容時拒絕載入。
- 契約測試：以錄下的 HTTP 回應重播執行每個插件的檢查案例（執行器與 fixture 格式見 ADR 0015），涵蓋 ADR 0011（遮蔽）、0012（媒體請求不帶憑證、`AuthRequirement`）、0013（錯誤對應）；插件 repo 的 CI 與插件作者本機都能跑。
- 測試：宿主 HTTP 拒絕 manifest 網域以外的請求；腳本無法讀取其他插件的 storage 與憑證。
- lint：UI 與 service 不得出現音源 id 字串常數或特定音源的型別：lint `fmp_source_id_literal`（ADR 0015）。
