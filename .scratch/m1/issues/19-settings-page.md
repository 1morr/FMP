# 19: 設定頁：外觀與播放

Status: done
Blocked by: 05、09、10
讀: brief §11；`docs/design/DESIGN.md` §1.4、§2.2、〈稿內不一致與實作注意〉第 1 點；`docs/design/settings.html`；architecture〈主要依賴〉（設定存 drift）；spec〈共同規則〉

## What to build

設定頁照稿的外殼（手機列表、桌面分類），只列 M1 有的分類：外觀（主題：跟隨系統、淺色、深色；強調色：無、堇紫、靛藍、青綠；語言：zh-TW、zh-CN、en；玻璃效果：完整、輕量、關閉，各一行說明實際效果，`DESIGN.md`〈稿內不一致與實作注意〉第 1 點）與播放（臨時播放倒退秒數）。設定存 drift，重啟後保留；改了立刻生效。

## 驗收

- [x] 設定頁在三種寬度、深淺色的截圖和 `settings.html` 對得上（M1 沒有的分類不出現）。（手機 iOS、窄視窗與桌面 macOS；玻璃效果列稿上沒畫，照擁有者同意的做法加）
- [x] 每個設定保存與還原有測試；改玻璃效果時所有玻璃一起切換，改倒退秒數時臨時播放照新值；schema 升級照流程。
- [x] 切換語言時三語的字串都在（`i18n_keys_test` 照過）。
- [x] 四平台實跑：改主題、強調色、玻璃效果、語言，重開後保留，讀回畫面。（照 spec〈共同規則〉縮成 macOS 加 iOS；Windows 跳過，見 Comments）
- [x] 語言多一個「跟隨系統」並設為預設（`settings.html` 的語言列）：系統語言不在三語內時用 zh-TW；桌面 ⌘,（Windows 用 Ctrl+,）從任何頁面開設定（`DESIGN.md` §10）；各有測試（2026-11-19 擁有者同意，文件審查發現）。
- [x] 無障礙照 `DESIGN.md` §10：這張新增的可聚焦元件有 2px 強調色焦點外框（offset 2）、手機點擊區補到 44（〈稿內不一致與實作注意〉第 2 點）、系統開「減少動態效果」時照 §3.4 改淡入淡出、不彈跳；各一條 widget 測試（2026-11-19 擁有者同意，文件審查發現）。
- [x] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。（`--skip-windows`）

## Comments
決定：語言「跟隨系統」、⌘, 與這張頁面的無障礙加進這張票（使用者同意）
Session 紀錄：2026-11-20 設定頁外觀與播放：drift 設定表（schema v6）與啟動時讀回、主題／強調色／語言（含跟隨系統）／玻璃效果／倒退秒數、手機列表與桌面分類欄、⌘,、無障礙與動態；macOS＋iOS 實跑與三種寬度深淺色比對 settings.html，完整閘門 --skip-windows 綠
決定：玻璃效果在手機是外觀第 4 列加選單（每項一行說明），桌面與平板是三列單選（使用者同意）
決定：玻璃效果列新畫一個疊層圖示，照 kit.js 的線條，kit.js 不改（使用者同意）
決定：手機與平板的強調色色點點擊區 44 相鄰，看起來間距 18（稿 10、14）（使用者同意）
決定：倒退秒數照舊版 0/3/5/10/15/30，0 寫「不倒退」；手機選單、桌面步進器（協調者代答）（Agent 定）
決定：設定存 drift 一張鍵值表，每個設定一列、值是字串（照 SharedPreferences），新增設定不改 schema（Agent 定）
決定：存的值每個選項明寫固定字串（玻璃 full/lite/off、語言 system/zh-TW…），不用 .name；讀不懂回預設並記 warning，新格式不做 migration（協調者轉達）（Agent 定）
決定：設定在 runApp 前讀回並先切好語言；寫不進去照樣生效、log 記一筆，下次開回到上次存的值（Agent 定）
決定：設定的狀態留在各模組原本的 provider（主題、語言、玻璃、倒退秒數），共用 data/ 的 SavedSetting，不新開模組（Agent 定）
決定：跟隨系統看系統第一個語言：Hant 或台港澳是 zh-TW、其他中文 zh-CN、英文 en、其他 zh-TW；系統換語言時跟著換（Agent 定）
決定：桌面與中寬度的兩欄照稿從內容區左緣起；頂列「設定」照各頁的左內距 24，比稿右 8（Agent 定）
決定：播放窗格的說明拿掉音質那半句（M2 才有）；選中的分類這次開 App 期間記住，預設外觀（Agent 定）
決定：⌘, 掛在 PlaybackShortcuts 的全域鍵盤處理：播放頁、輸入框裡也有作用，對話框與選單開著時不攔（Agent 定）
決定：實跑系統動作加 shortcut（System Events 拉前景送 ⌘＋鍵），驗證選單列的 Preferences… 沒吃掉 ⌘,；CGEventPostToPid 送不到（Agent 定）
決定：動態照〈狀態變化對照〉：選取（色點環、預覽圖環、勾、分類膠囊滑動）spring，值與窗格換內容、換主題 out 280；選單交給 19d（Agent 定）
決定：讀「減少動態效果」加共用入口 FmpMotion.reduced／selection，這頁經它讀；其他頁留給 19d（Agent 定）
決定：這頁本來就只有淡入淡出，減少動態效果的窗格與選單測試兩種設定都綠（協調者同意）（Agent 定）
決定：桌面步進器與語言選單鈕照稿看起來 24 高，點擊區補到 28（DESIGN.md §10）；色點環照稿離色點 4–6（Agent 定）
決定：實跑情境三支：settings_states_run（不聯網，照稿截圖）、settings_run 接 settings_restore_run（真開 App，首頁照常抓一次榜）（Agent 定）
Windows 跳過：建置、integration_test 與實跑都沒做。補驗看設定頁三種寬度、Ctrl+, 從任何頁開設定、改主題／強調色／玻璃／語言重開後保留、輕量玻璃的外觀
code-review 未處理：PlaybackShortcuts 現在也管 ⌘,，名字沒改（改名牽動多檔，留給之後）
code-review 未處理：密度沿用 `bool touch` 一路傳、存回來的設定是 `Map<String, String>`，照現有寫法
code-review 未處理：glassLabel／glassHint 各一個 switch、分類欄圖示方塊與 SettingsIconBox 相似、選單說明字級與 SettingsStyle 重複、測試認玻璃級數的寫法和 glass_test 重複
code-review 未處理：settings.html 沒有玻璃效果列與 18 的色點間距，設計稿待同步
變更：Added｜設定｜設定頁：手機是外觀、播放兩組列表，桌面與平板是分類欄加內容
變更：Added｜外觀｜可以選主題（跟隨系統、淺色、深色）與強調色（無、堇紫、靛藍、青綠），立刻生效、重開後保留
變更：Added｜外觀｜可以選介面語言（跟隨系統、繁體中文、简体中文、English），立刻生效；跟隨系統時系統語言不在三種裡就用繁體中文
變更：Added｜外觀｜可以選玻璃效果（完整、輕量、關閉），每個選項寫明實際效果，整個 App 一起切換
變更：Added｜臨時播放｜可以設定臨時播放結束後倒退幾秒（不倒退、3、5、10、15、30 秒）
變更：Added｜外殼｜桌面在任何頁面按 ⌘,（Windows 用 Ctrl+,）打開設定
