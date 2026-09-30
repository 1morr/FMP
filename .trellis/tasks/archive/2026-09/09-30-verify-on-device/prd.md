# app 的 verify-on-device skill（M1 PR 11）

父任務：`../09-28-m1-skeleton-tracer`（implement「11.」、design §6）。依據 ADR 0027（決定 1–3、如何確認）與父任務 prd 的決定 1（舊 skill 改名 `verify-legacy-on-device`，`verify-on-device` 這個名字給 `app/`）。

## 做什麼

1. **新 skill**：`.claude/skills/verify-on-device/`。
   - `SKILL.md` 是閉環：啟動 → 執行 → 觀察 → 操作 → 收尾；做不到就具名回報 blocker。
   - 預設模式：dev flavor 加測試插件；真實連線只在 ADR 0027 §決定 2 的條件下使用。
   - 平台分工照 ADR 0027 §決定 3：每個 PR 都驗 Android 與 Windows。
   - 回報格式必含「平台」與「模式：重播／真實」，真實時列出做了哪些請求。
   - `references/android.md`：
     - 模擬器；
     - 安裝 dev APK；
     - `run-as` 把插件複製進 `files/`；
     - 以 `am start ... --esal dart_entrypoint_args` 帶開發入口的參數，並說明逗號會切陣列；
     - Git Bash 要設 `MSYS_NO_PATHCONV=1`；
     - `logcat -s flutter`；
     - `dumpsys audio` 的焦點紀錄；
     - `screencap`。
     - 絕對不能動模擬器上的舊版 `com.personal.fmp`，prod APK 不要裝上去。
     - 模擬器若是 `-no-audio` 啟動的，要寫進回報。
   - `references/windows.md`：
     - `flutter build windows --flavor dev --debug` 與產物路徑；
     - dev 是單一實例，其他 worktree 的 FMP Dev 也算；
     - log 在 `userdata-dev\logs\fmp.jsonl`；
     - 用 MSAA 讀畫面文字、點按鈕；
     - 只截 App 視窗，截圖不得含個人資訊；
     - 用 SMTC 探針（M2 才用得到，先寫明）。
   - `references/runtime-state.md`：改寫成 `app/` 的現況：
     - drift 的 `fmp.db`；
     - dev 與 prod 的資料目錄：Windows 免安裝版是 `userdata-dev/`、`userdata/`，安裝版在 `%APPDATA%`；Android 是 `files/`；
     - 插件資料表；
     - log 檔的格式；
     - 怎麼清成乾淨狀態（先看再刪，只刪 dev 的資料）；
     - 開發入口 `--fmp-dev-plugin=`、`--fmp-dev-playback[=<曲目鍵>]` 與環境變數 `FMP_DEV_PLUGIN`。
   - `scripts/`：
     - 從舊 skill 複製 `ax_flatten.py`、`msaa_tree.ps1`、`smtc_probe.ps1`，舊 skill 原樣保留、不共用（design §6）；
     - 腳本內寫死的舊路徑、程序名稱，改成 `app/` 的；
     - 另外加視窗截圖腳本，草稿在本任務目錄的 `window_shot_draft.ps1`：以 `PrintWindow` 只截 App 視窗。
2. **`app/AGENTS.md` 的驗證段**（ADR 0027 §如何確認）：
   - 寫明預設重播或測試插件、真實連線的條件、每個 PR 都驗 Android 與 Windows；
   - 回報格式要有「平台」與「模式」；
   - 指向這個 skill；
   - 已有的內容整合進去，不重複。
3. **根目錄 `AGENTS.md` 的地圖**：`.claude/skills/` 那一列補上 `verify-on-device`。

## 驗收

- [ ] 用新 skill 照步驟，在 Windows 與 Android 模擬器各把 dev 版啟動到首頁，也就是目前的身分頁。回報附平台與模式。這一步由主對話執行。
- [ ] 三支複製過來的腳本在 `app/` 的 dev 版上實際跑過至少一次；SMTC 目前沒有東西可讀，寫明。
- [ ] skill 內容沒有舊專案的路徑或名稱殘留；個人路徑一律以佔位符表示。
- [ ] 文件用繁中，指令、路徑、識別符保留原文。
