# FMP 音源文檔對齊審查

## Findings

### Finding 1：Bilibili 直播串流被描述為 HLS，但實作仍取 `durl[0]`

- 文檔位置：`lib/data/sources/AGENTS.md:11` 宣稱「Live room audio streams use HLS」。
- 代碼驗證：`lib/data/sources/bilibili_source.dart:1119` 的註解稱 HLS，但實作呼叫 `/room/v1/Room/playUrl` 後讀取 `data.durl`，並直接回傳 `durl[0]['url']`，見 `lib/data/sources/bilibili_source.dart:1135` 與 `lib/data/sources/bilibili_source.dart:1140`。
- 代碼驗證：Radio 路徑同樣從 `durl` 取第一個 URL，見 `lib/services/radio/radio_source.dart:280` 與 `lib/services/radio/radio_source.dart:286`；`lib/services/radio/radio_source.dart:285` 的「優先使用 HLS，然後是 FLV」也沒有被選流邏輯驗證。

### Finding 2：`getAudioUrl()` 的回傳型別被文檔寫成 `AudioStreamResult`

- 文檔位置：`lib/data/sources/AGENTS.md:116` 到 `lib/data/sources/AGENTS.md:117` 寫成「`AudioStreamConfig` is passed to source `getAudioUrl()` and returns `AudioStreamResult`」。
- 代碼驗證：實際 `BaseSource.getAudioStream()` 才回傳 `Future<AudioStreamResult>`，見 `lib/data/sources/base_source.dart:182` 到 `lib/data/sources/base_source.dart:186`。
- 代碼驗證：`BaseSource.getAudioUrl()` 是簡化包裝，只回傳 `Future<String>`，並從 `AudioStreamResult.url` 取值，見 `lib/data/sources/base_source.dart:190` 到 `lib/data/sources/base_source.dart:197`。

## Evidence

- `lib/data/sources/AGENTS.md:11` 將 Bilibili live 描述成 HLS；`lib/data/sources/bilibili_source.dart:1135` 到 `lib/data/sources/bilibili_source.dart:1140` 與 `lib/services/radio/radio_source.dart:280` 到 `lib/services/radio/radio_source.dart:290` 顯示目前實作以 `durl[0]` 作為串流 URL，沒有檢查或排序 HLS/FLV。
- `lib/data/sources/AGENTS.md:116` 到 `lib/data/sources/AGENTS.md:117` 混淆 `getAudioUrl()` 與 `getAudioStream()`；`lib/data/sources/base_source.dart:182` 到 `lib/data/sources/base_source.dart:197` 顯示正確契約是 `getAudioStream()` 回傳元資料，`getAudioUrl()` 只回傳 URL 字串。

## Source-specific reason if applicable

- Bilibili live 是 source-specific 差異：直播 API 的回應形狀和一般影片 DASH/durl 不同，文檔應避免把目前 `durl` 實作概括成 HLS，除非程式碼實際切換到可驗證的 HLS 選流。
- `getAudioUrl()` 型別錯誤是 shared contract 問題，不屬於單一音源；它會影響 source adapter、download、playback handoff 對 `AudioStreamResult` metadata 的理解。

## Suggested direction

- 對 Finding 1：二選一收斂。若目標是 HLS，讓 Bilibili live/radio 實作明確解析並選擇 HLS URL，再保留文檔；若目前 `durl[0]` 是設計，將文檔改成「直播串流從 Bilibili live playUrl `durl` 取得，headers 使用 live policy」，並移除未驗證的 HLS 優先描述。
- 對 Finding 2：將 `lib/data/sources/AGENTS.md:116` 到 `lib/data/sources/AGENTS.md:117` 改為「`AudioStreamConfig` is passed to `getAudioStream()`; `getAudioStream()` returns `AudioStreamResult`, while `getAudioUrl()` extracts only the URL」。

## Instruction docs accuracy notes

- `docs/agents/` 目前不存在；本次審查未把它當成當前規範來源。
- 本次只採納由代碼驗證的描述性內容；規範性要求例如 `SourceHttpPolicy` 集中 headers、auth-for-play 邊界、quality fallback，只在可由代碼對照時納入判斷。
- `.serena/memories/` 中的補充記憶未發現高於上述兩項的音源文檔對齊問題；若與 `AGENTS.md` 衝突，應以 `AGENTS.md` 為準。
