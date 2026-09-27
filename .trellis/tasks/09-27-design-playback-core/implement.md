# 執行計畫：第 13 項（設計任務，只產出文件）

1. 核准後寫 `docs/adr/0018-playback-core.md`（依 `docs/adr/template.md`），內容取自 `design.md` §1–§10；被否決的方案：
   全平台 media_kit、佇列真相放原生播放清單、電台繞過控制器的例外、隨機模式下「下一首播放」插隨機位置、錯誤只在 queue 模式跳過、錯誤以字串存於狀態。
   說明它延續舊 ADR 0003（兩個後端）的形狀、適用於 `app/`。
2. ADR 0014：`resolveStream` 輸入加上平台可播格式、輸出為候選串流清單；`live` 能力提供直播串流與直播狀態。
   ADR 0009：平台能力宣告加上「音訊後端與可播格式」。ADR 0017：`fmp_periodic_timer_owner` 的播放模組指向 ADR 0018。
3. `phase2-plan.md`：§3 第 13 項標 ✅（ADR 0018）；§7 第一個里程碑實測加入「兩個後端的前瞻交接與 Android 音訊焦點不在換歌時釋放」；
   §8 延後實測加入「蘋果平台 AVPlayer 對 B 站 DASH 音訊與直播 HLS 的支援」；§10 交接段更新，下一項 14 音樂庫與同步。
4. 驗證：Mermaid 以 mermaid-cli 渲染（設計圖已驗）；`git grep` 確認 ADR 間引用。
5. `task.py finish`、`task.py archive design-playback-core --no-commit --skip-branch-validation`；分開提交 ADR 與歸檔，推上 `docs/audit`。

回退：全部是文件，revert 對應 commit 即可。
