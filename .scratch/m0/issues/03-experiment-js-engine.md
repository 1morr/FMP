# 03: 實驗：JS 引擎

**What to build:** 用實驗決定插件跑在哪個 JS 引擎：`fjs` 或 `flutter_js`（加自編 QuickJS）。標準照 brief §17：四平台同一引擎、能中斷無窮迴圈、能設記憶體上限、支援 async。也量出引擎與 isolate 的配置（plan §1.1）。結論給擁有者確認後寫回 brief 與 plan。

讀：brief §5.3、§17、事實 K7、R6、R7；plan §1.1、§1.4、§6 P2；ADR 0038；spec〈共同規則〉的實驗規則

**Blocked by:** None (can start immediately)

**Status:** done

- [x] 實驗程式在 `scripts/experiments/` 底下，可重跑，附怎麼跑的說明；換版本時能重量。
- [x] 兩個候選在四平台各自實測四項標準，另測一次 async 宿主呼叫（JS 呼叫 Dart 提供的 async 函式並拿回結果）；結果做成表，含版本號與平台。
- [x] 重驗事實 K7，更新它在 brief 的寫法與可信度。
- [x] 結論草稿（選哪個、isolate 配置、已知限制）先給擁有者確認；確認後寫進 brief §18（事實）、brief §17 移除該條、plan §1.1、§1.4、§6 P2 更新。
- [x] 如果兩個都不滿足四項標準：停下來回報，不自己放寬標準。

## Comments

- 結論（擁有者 2026-11-11 確認）：插件的 JS 引擎用 fjs 3.3.2。結果表、量測方法與怎麼重跑在 `scripts/experiments/js-engine/README.md`，原始結果在同目錄 `results/*.json`；寫進 brief 事實 K7（改寫）、K11（新增），brief §17 那條刪除，plan §1.1、§1.4、§4 環境、§6 P2 更新。flutter_js 0.8.7 沒過「中斷無窮迴圈」（四平台），Android、Windows 也沒過「記憶體上限」，四項標準只有 fjs 全過，所以沒有走「兩個都不滿足就停下」那條。
- 擁有者同意的提議：票 08 的驗收加一條「建立引擎時只開白名單內建模組」的測試（fjs 自帶 fetch 會繞過宿主的網域白名單）。這張票不實作。
- 舊版設定：根目錄 `analysis_options.yaml` 的 `analyzer.exclude` 加了 `scripts/**`。原因：每個實驗是獨立的 Flutter 專案，根目錄的 `flutter analyze`（舊版 `ci.yml`）會掃進去並因為沒 pub get 而報錯。舊版的行為不變。
- 環境變更：`winpc` 的 rustup default host 從 `x86_64-pc-windows-gnu` 改成 `x86_64-pc-windows-msvc`（作用中的工具鏈原本就是 msvc）。gnu 時 Cargokit 的 `rustup run stable` 拿 gnu 工具鏈，`libloading` 缺 `dlltool.exe` 而建置失敗。改回：`rustup set default-host x86_64-pc-windows-gnu`。
- 實驗中的取捨：Android 不用 `flutter test`，因為同機別的 session 重啟 adb daemon 時它會判失敗；改成 App 自己跑完寫檔、主機事後取回。中斷是否成功看行程 CPU 時間（`getrusage`／`GetProcessTimes`），不只看 Dart 的 Future。
- 事實 K7 原文的「iOS 要 `use_frameworks!`」沒有重驗（實驗只用了 Podfile 預設），不選 flutter_js 後用不到，改寫時拿掉。
- code-review（cb37933e 起）已處理：`flutter create` 寫進 iOS 專案檔的 Apple Team ID 已移除並 amend（commit 沒推出去過）；記憶體上限改成要 `out of memory` 且之後 1+2=3 才算過；中斷測項移到最後，免得 flutter_js 留下的空轉執行緒污染前面的計時；補量「卡住的引擎會不會拖累其他引擎」與「await 之後、setTimeout 回呼裡的迴圈能不能中斷」（因此發現 fjs 只有 2 條 JS 執行緒）；版本號由 `summarize.py` 和 `pubspec.lock` 對照。
- code-review 未處理（不做，理由）：
  - fjs 在 Apple 用的預編譯 xcframework、flutter_js 在 Windows 的 2021 年 dll，都沒核對和宣稱的版本同一份原始碼：只比 stack 格式分得出 QuickJS 與 JSC，分不出版本；不影響選擇，README 已註明。
  - flutter_js 中斷「timeout 生效」那條分支用絕對門檻，和 `loopStopped` 的相對門檻不一致：四平台都沒走到那條分支。
  - flutter_js 沒量 await 之後與 timer 裡的迴圈：頂層迴圈已經中斷不了。
- 2026-11-11 下午 `winpc` 藍屏重開（bugcheck 0x1E，核心模式例外），那時一次 Windows 執行因連線中斷失敗，已重跑；現在的兩份 Windows 結果都在重開之後。
