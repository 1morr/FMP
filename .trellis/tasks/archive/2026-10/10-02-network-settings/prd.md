# 「網路」設定組：快取上限、用量、清除（M2 PR 5）

> 父任務：`.trellis/tasks/10-01-m2-full-playback`。技術設計在父任務 `design.md` §3.3（「網路」組）、§3.5（schema 版本與測試）、§4.4、§9.8；本檔只列做什麼與驗收。

## 目標

使用者能在設定頁看到封面快取用了多少、改快取上限、一鍵清除快取。設定頁從單頁改成分組，寬螢幕是左右兩欄（ADR 0024 §決定 6）。

## 做什麼

1. **資料**：
   - `network_settings` 表（主資料庫 schema bump，這是 v2）：只有「快取上限」，可空，空＝平台層宣告的預設（`PlatformCapabilities.cache`）。
   - repository 與 Notifier 照 M1 外觀組的形狀（`app/AGENTS.md` § 設定、`.trellis/spec/app/settings/index.md`）。
   - 照 `.trellis/spec/app/data/index.md` § 改 schema 走完整流程：快照、`stepByStep`、三種 migration 測試（新表沒有舊資料，「不改使用者值」以升級後 `appearance_settings` 的值不變代表）。
2. **接到快取庫**：
   - `cacheStoreProvider` 的上限改讀這個設定（PR 4 目前讀平台預設）；
   - 改上限時呼叫 `CacheStore.setLimit`，馬上淘汰到新上限以下。
3. **設定頁**：
   - 改成分組：外觀、網路（「播放」組在 PR 8 之後才有列，這個 PR 不加空的組）。
   - expanded 以上 list-detail：左邊分組、右邊內容；較窄時是分組清單，點進去看內容。照 ADR 0024 §決定 6 與 M1 既有的版面斷點。
   - 「網路」組三列：
     - 快取上限：128／256／512／1024 MB，未設定時顯示平台預設並標明；
     - 封面用量：以 `CacheStore.watchUsage()` 即時顯示（M2 只有「封面」一類），格式化成 KB／MB；
     - 「清除快取」：確認框後清 `CacheStore.clear()`，並清 Flutter 的 `ImageCache`（`imageCache.clear()`、`clearLiveImages()`；PR 4 留下的）；清完用量顯示 0。
   - 文案三語言（繁中、簡中、英文）。
4. **文件**：`app/AGENTS.md` § 設定（新組）、§ 介面（設定頁版面）、§ 資料層的快取庫（上限來源）；需要時更新 spec。

## 不做

- 「播放」組的任何列（PR 8 起）。
- 快取以外的網路設定（M3）。
- 舊版快取設定的匯入（ADR 0016 §決定 3：不匯入）。

## 驗收

- [ ] 測試：
  - `.trellis/spec/app/settings/index.md` 第 6 步的五種；
  - migration 三種，`schema_test`；
  - 改上限後馬上淘汰（以 `CacheStore` 的假或真實暫存目錄）；
  - 清除後用量顯示 0，且 `ImageCache` 被清；
  - 設定頁在 400／1000 寬的 guideline 測試；
  - list-detail 的版面測試（寬窄兩種）。
- [ ] 驗證清單全綠（父任務 implement.md「每個 PR 的固定流程」第 5 步），含 `build_runner` 後沒有實質變動、`dart run slang`。
- [ ] 實機（主對話做；真實連線，延續 PR 4 的最少操作）：兩平台看用量、改上限、清除後封面重新下載。
