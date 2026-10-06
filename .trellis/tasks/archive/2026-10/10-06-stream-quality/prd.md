# 音質與格式偏好、`expiresAt` 契約（M2 PR 8）

> 父任務：`.trellis/tasks/10-01-m2-full-playback`。技術設計在父任務 `design.md` §7.4 末段（音質與格式偏好進插件）、§10（`1morr/fmp-plugins` 的改動、`expiresAtPattern`、遮蔽名單拿掉 `deadline`）、§3.3（`audio_quality`、`audio_format_priority` 欄位，表已在 PR 10 建好，列舉在 `lib/domain/stream_preferences.dart`）、§12 第 4、5 條（擁有者已核准）。執行清單在父任務 `implement.md`「8.」。本檔只列做什麼與驗收。

## 目標

使用者能選音質（高／中／低）與格式偏好（Opus 優先／AAC 優先）；選擇送進插件，B 站插件依音質挑 DASH 音軌；契約測試能核對 `expiresAt` 與網址內的期限一致。

## 做什麼

### FMP（分支 `feat/app-stream-quality`）

1. **`StreamRequest.quality`**（可選，`high`／`medium`／`low`）：DTO、`fmp-plugin.d.ts`、`sourceDtoShapes`、`type_definitions_test.dart`；`hostApiVersion` 維持 1。
2. **格式偏好**：宿主把平台的 `formats` 依使用者的編碼順序重排後送出（不加欄位）。
3. **控制器／解析**：解析時帶上目前的音質與格式偏好；`StreamResolver` 的快取鍵已含格式順序，加上音質（PR 7 的鍵＝插件實例＋曲目鍵＋格式順序）。換偏好後重新解析。
4. **設定**：`playbackPreferencesProvider` 加音質、格式偏好兩個 setter；設定頁「播放」組加兩列（預設：高、Opus 優先；舊版 `audioQualityLevelIndex`、`audioFormatPriority` 對應見 design §3.3）。三語言。
5. **契約執行器**：支援 `checks.json` 的 `expiresAtPattern`（一個擷取群組，單位 unix 秒），逐一核對候選的 `expiresAt` 與網址內的期限一致；`FmpChecks` 型別。雙向測試：不一致會紅、改無關欄位不紅。
6. **遮蔽名單**：`redaction_lists.dart` 的 `_bilibiliSigned` 拿掉 `deadline`（公開時間戳，不是憑證；`upsig` 等簽名參數照舊遮蔽，網址照樣不能用）。`app/` 內既有 fixture 照舊通過「再遮一次不變」（`fixture_scan_test.dart`）。這是改遮蔽名單：審查要試著攻破。
7. **ADR 0014 §決定 5** 加一行補充（`StreamRequest.quality`），與 PR 12 加的 `previewOnly` 那行並列。
8. 文件：`app/AGENTS.md`（§ 插件、§ 播放、§ 設定）、相關 spec；每條寫閘門。

### fmp-plugins（`../fmp-plugins`，分支 `feat/bilibili-quality`，擁有者自己的 repo，自己的 PR）

9. **B 站 `resolveStream` 讀 `quality`**：DASH 音訊依頻寬排序，選中的層級放最前面，其他層級依序在後當備援。高＝最高頻寬、中＝中間、低＝最低（舊版 `audio_stream_quality_fallback.dart:9-20`）；沒給時當 `high`（目前行為）。
10. **`checks.json`**：`resolveStream` 輸入加 `"quality": "high"`，加 `expiresAtPattern`：`[?&](?:deadline=|hdnts=exp=)(\d+)`。
11. **重錄 `resolveStream` 的 fixture**：真實連線，一個案例（約三個 GET），ADR 0027 §決定 2 的最少操作；遮蔽後的網址保留 `deadline`、沒有任何憑證。主對話會逐檔人工確認。
12. README 若需要同步就改。

## 不做

- 其他 `playback_settings` 欄位的 setter（各自的 PR）。
- 網易的 `level`（M3）。
- 下載用途的偏好（M6）。

## 驗收

- [ ] 測試：settings（音質、格式兩個 setter）；快取鍵含偏好（換偏好後重新解析）；`formats` 的順序；`type_definitions_test.dart`；`contract_runner_test.dart` 的 `expiresAtPattern`（不一致會紅、改無關欄位不紅）；`fixture_scan_test.dart`；設定頁兩列。
- [ ] `FMP_PLUGIN_DIR=<fmp-plugins>/bilibili flutter test test/plugins/contract/contract_test.dart` 重播通過（新 fixture、新 checks）。
- [ ] 驗證清單全綠（父任務 implement.md「每個 PR 的固定流程」第 5 步）。
- [ ] 實機（主對話做；真實連線，因為改動含插件）：兩平台把音質切到「低」播一首 B 站，`Opening stream` 的 `bitrate` 是最低層。只搜尋一次、播一首。
