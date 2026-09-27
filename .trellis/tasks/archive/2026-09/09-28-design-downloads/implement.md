# 執行計畫：第 11 項（設計任務，只產出文件）

1. [x] 核准後寫 `docs/adr/0020-downloads-and-permissions.md`（依 `docs/adr/template.md`），內容取自 `design.md` §1–§9；被否決的方案：
   自寫 isolate 下載器、`flutter_downloader`（無桌面）、SAF URI 下載（不能續傳）、依歌單分資料夾、依歌手分資料夾、下載最高音質含 Opus、
   啟動掃描以資料夾名重建關聯、掃不到就清路徑、播放時找不到檔就永久清路徑。說明它延續舊 ADR 0004 的 Android 儲存做法、適用於 `app/`。
2. [x] ADR 0014／0018：`resolveStream` 輸入加上用途（播放／下載）。ADR 0009：`PermissionGateway` 與權限能力宣告指向 ADR 0020。
3. [x] `phase2-plan.md`：§3 第 11 項標 ✅（ADR 0020）；§8 延後實測加入「加入下載的里程碑：`permission_handler` 在 Windows 是否使 FMP 出現在位置權限清單；
   `audio_metadata_reader` 寫入的標籤能被常見播放器讀到；`background_downloader` 在 Android 以 `MANAGE_EXTERNAL_STORAGE` 搬移到使用者資料夾」；
   §10 交接段更新，下一項 15 歌詞。
4. [x] 驗證：Mermaid 以 mermaid-cli 渲染（設計圖已驗）；`git grep` 確認 ADR 間引用。
5. [x] `task.py finish`、`task.py archive design-downloads --no-commit --skip-branch-validation`；分開提交 ADR 與歸檔，推上 `docs/audit`。

回退：全部是文件，revert 對應 commit 即可。
