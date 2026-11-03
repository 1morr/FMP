# Research: iOS 簽章與散佈（免費 Personal Team vs 付費 Developer Program）

- **Query**: ADR 0009 的「iOS 不上架、GitHub 發 IPA、AltStore／SideStore 側載」在 2026 年的現況；免費與付費帳號的差別；這台 Mac 的簽章狀況；flavor 與 bundle id；CI 的不簽名建置與模擬器整合測試；建議。
- **Scope**: mixed（Apple 官方說明頁與 SideStore／AltStore 文件、這台 Mac 的唯讀狀態、`--no-codesign` 建置實測）
- **Date**: 2026-11-04
- 證據標記：**實測**、**文件**（附連結）、**原始碼**。
- 隱私：不寫帳號名、email、UDID、裝置名稱；家目錄寫 `<家目錄>`。Team ID 也不寫（同 `app/AGENTS.md` § App 身分：本機簽章資訊不進 repo），寫成 `<Team ID>`。

## 結論先講

1. **免費帳號（Personal Team）能做 FMP 的全部必要能力**：Background Modes（audio）、Keychain、App Groups 都在免費可用的 capability 表內（文件），本機的免費 profile 也實際帶有 `keychain-access-groups`（實測）。**不能用**：Push notifications、Associated Domains、Siri、Time Sensitive Notifications 等（文件）。Live Activity 的本機起停不需要 capability，但要 Widget Extension（多一個 App ID）；用 push 更新 Live Activity 需要 Push（付費）（文件＋推論，見 §1）。
2. **免費的硬限制**：profile 7 天、10 個 App ID（7 天內）、3 台裝置、每台 3 個 App（文件：Apple）。SideStore 文件說免費帳號「3 個 App 含 SideStore 自己」，所以 FMP prod + FMP Dev 加 SideStore 剛好用滿（文件：SideStore）。
3. **付費（US$99／年）**：development／ad hoc profile 長效、ad hoc 最多 100 台／類／年、TestFlight 內部測試最多 100 位 App Store Connect 使用者、build 90 天、內部測試不送審（文件）；可以完全不上架自用。development／ad hoc 的簽章在 2021 後的團隊需連 `ppq.apple.com` 驗證首次啟動（文件）。
4. **這台 Mac（實測，唯讀）**：有一張有效的 Apple Development 憑證（OU `<Team ID>`，效期 2026-10-29 至 2027-10-29）；`devicectl` 列出數個已配對項目，其中一支 developer mode 開啟；`Provisioning Profiles` 目錄只有 1 份 profile，屬於同一個 team、是別的工具的 XCTest runner 的 App ID，7 天效期；**沒有 FMP 的 profile，也沒有 FMP 的 App ID 註冊紀錄**。
5. **CI**：現有 `app-build-ios` 已跑 `--no-codesign` 的 prod release 與 dev debug（原始碼）；`flutter build ipa --no-codesign` 只產 `.xcarchive` 不產 IPA，要自己 zip `Payload/Runner.app`（實測）；`app-release.yml` 目前沒有 iOS job。模擬器整合測試目前沒有。
6. **bundle id**：`com.personal.fmp` 本身沒有被 App Store 的 app 使用（iTunes lookup 回 0 筆，實測），但免費／付費帳號都是「註冊時先搶先贏、全域唯一」，本機無法在不改帳號狀態的前提下確認有沒有人註冊過（沒實測）。要不要加前綴看擁有者願不願意第一次簽章遇到衝突時再改，見 §3。

## 1. 免費 Personal Team 與付費 Program 的差別（2026）

### 免費

| 項目 | 內容 | 證據 |
|---|---|---|
| profile 效期 | 簽出來的 App 7 天後過期，要重簽重裝 | 文件：[Developer account overview](https://developer.apple.com/help/account/getting-started/developer-account-overview/)（"Provisioning profiles ... will expire 7 days from issuance"）；實測：本機免費 profile 建立 2026-10-29、到期 2026-11-05 |
| App ID | 最多 10 個，7 天後過期 | 同上 |
| 裝置 | 最多 3 台 | 同上 |
| 每台 App | 最多 3 個 | 同上 |
| 側載工具 | SideStore：「免費帳號只能裝 3 個 App（含 SideStore）；每週最多 10 個不同 App（App ID）」；用 VPN 讓 iOS 接受、背景自動 refresh 以免 7 天到期 | 文件：[SideStore FAQ](https://docs.sidestore.io/docs/faq) |
| AltStore Classic | 要一台跑 AltServer 的電腦與 iPhone 在同一個 WiFi 才能 refresh（連不上時要接線） | 文件：[AltStore 疑難排解](https://faq.altstore.io/altstore-classic/troubleshooting-guide) |
| 憑證 | Apple Development 憑證效期 1 年（profile 才是 7 天） | 實測：本機憑證 notBefore 2026-10-29、notAfter 2027-10-29 |

可用的 capability（Apple 的 [Supported capabilities (iOS)](https://developer.apple.com/help/account/reference/supported-capabilities-ios/) 表，「Apple Developer」欄＝只同意協議的免費帳號；我從頁面 HTML 的核取圖示解析）：

| Capability | 免費 | 付費 (ADP) |
|---|---|---|
| Background modes（含 audio） | 是 | 是 |
| Keychain sharing | 是 | 是 |
| App groups | 是 | 是 |
| Maps、HealthKit、Wireless Accessory Configuration | 是 | 是 |
| Push notifications | 否 | 是 |
| Associated domains、Sign in with Apple（僅 ADP）、Siri | 否 | 是 |
| Time Sensitive Notifications | 否 | 是 |
| Sustained Execution | 否 | 是 |
| Network extensions、Personal VPN、Multipath、Access WiFi information | 否 | 是 |
| Increased Debugging Memory Limit | 否 | 是 |

- **Background Modes audio**：免費可用（文件表）。`UIBackgroundModes: audio` 是 Info.plist 鍵，本來就不需要 profile 的 entitlement（推論，未實測）。
- **Keychain**：免費可用（文件表）。本機免費 profile 的 entitlements 含 `application-identifier`、`get-task-allow`、`keychain-access-groups`、`team-identifier`（實測，讀 `security cms -D` 的輸出）。所以 `flutter_secure_storage` 在 iOS 預設的 data protection keychain 用得上，這點與 macOS（沒有 profile，ADR 0036 §決定 3）不同。
- **App Groups**：免費可用（文件表）。
- **Push**：免費不可（文件表）。FMP 沒有遠端推播需求。
- **ActivityKit／Live Activity**：能力表**沒有** ActivityKit 列。ActivityKit 要 Info.plist 的 `NSSupportsLiveActivities` 與一個 Widget Extension target（文件：[ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)）。App 自己用 ActivityKit 起、更新、結束 Live Activity 不需要 Push；「ActivityKit push notifications」更新才需要 Push capability（文件，同頁）。Widget Extension 有自己的 bundle id，也要一個 App ID，會吃 10 個 App ID 的額度與每台 3 個 App 的額度（**推論**：SideStore 文件沒有明說 extension 算不算「App」）。**沒有實測**。
- 免費與付費的簽章差別對 FMP 的實際功能（背景播放、Now Playing、Keychain）沒有影響；差別在「7 天」與「3 個 App」。

### 付費（US$99／年，[Apple Developer Program](https://developer.apple.com/programs/whats-included/)：「99 USD per membership year」）

| 項目 | 內容 | 證據 |
|---|---|---|
| development／ad hoc profile | 效期一年（Apple 在我抓到的幾個說明頁沒有明寫數字；一般認知與 Xcode 行為） | 未在官方頁確認；**不確定** |
| ad hoc 裝置 | 每個產品線每個會員年最多 100 台 | 文件：[Devices overview](https://developer.apple.com/help/account/devices/devices-overview/) |
| PPQ | 2021-06-06 之後建立的團隊：development／ad hoc 簽章的 iOS App 首次啟動要連 `ppq.apple.com` 驗憑證；連不上 App 可能無法啟動；有 7 天的「離線 profile」選項 | 文件：[Provisioning profile updates](https://developer.apple.com/help/account/provisioning-profiles/provisioning-profile-updates/) |
| TestFlight | build 最多測 90 天；內部測試最多 100 位 App Store Connect 使用者；外部測試（最多 10,000 人）的第一個 build 才送審；build 必須上傳到 App Store Connect（要先建 App 紀錄） | 文件：[TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/) |
| Push、Associated Domains、Siri 等 | 可用 | 文件：能力表 |

- **不上架可不可以長期自用**：可以。兩條路：(a) development／ad hoc 簽章（註冊自己的 iPhone，安裝一次，profile 一年）；(b) TestFlight 內部測試（只有自己一人，不經外部審查，build 每 90 天要重傳）。TestFlight 內部測試「不送審」是文件的推論（頁面只說外部測試要送審，沒有說內部測試要或不要）；**不確定**內部 build 是否仍會被自動檢查。
- ADR 0009 §決定 5 的理由是 App Store Guideline 5.2.3（下載第三方媒體）與不上架；TestFlight 仍是 Apple 的散佈管道，擁有者要先接受「用 TestFlight 發 FMP」是不是在 Apple 的條款下。**我沒有查 TestFlight 對此類 App 的審查政策**。
- 付費帳號才有 data protection keychain 以外的選項（macOS 的 ADR 0036 §決定 3 提到「付費帳號 + `keychain-access-groups`」）；iOS 兩種帳號都有。

## 2. 這台 Mac 的狀況（唯讀，實測）

| 檢查 | 結果 |
|---|---|
| `security find-identity -v -p codesigning` | 1 張有效的 Apple Development 憑證（OU = `<Team ID>`；憑證 notBefore 2026-10-29、notAfter 2027-10-29） |
| `xcrun devicectl list devices` | 5 筆已配對項目；其中 1 筆 `connected`，另 1 筆 developer mode 狀態為 enabled（其餘 `None`）；都是 iOS 27.x。沒有讀名稱、UDID。沒有安裝任何東西 |
| `<家目錄>/Library/Developer/Xcode/UserData/Provisioning Profiles` | 1 份 `.mobileprovision`：team `<Team ID>`、`iOS Team Provisioning Profile`（Xcode 自動簽章產生）、1 台裝置、2026-10-29 建立、2026-11-05 到期（7 天），App ID 是別的工具的 XCTest runner（明確 id，尾巴是 `.<小寫 Team ID>.xctrunner`），entitlements 只有 application-identifier、get-task-allow、keychain-access-groups、team-identifier；沒有 FMP 的 profile |
| `app/ios/Runner.xcodeproj/project.pbxproj` | 有未提交的 Podfile、Pods、pbxproj 變動（任務進行中的既有狀態）；各 target 是 `CODE_SIGN_STYLE = Automatic`，沒有 `DEVELOPMENT_TEAM`；沒有 macOS 那套 `Signing.xcconfig`（原始碼） |

- 免費帳號的 profile 7 天、憑證 1 年這兩個數字都被本機資料印證。
- 這份 runner profile 的 bundle id 帶了 Team ID 後綴，是該工具為了在免費帳號上避免衝突的做法；它顯示 Xcode 自動簽章會在第一次建置時為明確 App ID 註冊並產生 profile（推論）。
- 在 Xcode 把 team 設成 `<Team ID>` 之前，自動簽章不會替 FMP 產生 profile；macOS 的做法（`Runner/Configs/Signing.xcconfig`，gitignore，放 `CODE_SIGN_IDENTITY` 與 `DEVELOPMENT_TEAM`）可以照搬到 iOS，免得 Team ID 進 repo（`app/AGENTS.md` § App 身分的 macOS 本機簽章段）。這是現況描述，不是決定。

## 3. flavor、bundle id 與 App 身分

### 現況（原始碼）

- `app/AGENTS.md` § App 身分：iOS／macOS bundle id prod `com.personal.fmp`、dev `com.personal.fmp.dev`，在 `ios/Runner.xcodeproj/project.pbxproj` 每個 build configuration 的 `PRODUCT_BUNDLE_IDENTIFIER`；`ios/` 有 `dev`、`prod`、`Runner` 三個 scheme（`xcshareddata/xcschemes/`）。
- 「iOS、macOS 的舊版沒有發過，prod 沿用 Android 的 `com.personal.fmp`」。所以 iOS 的 bundle id 沒有舊資料或憑證要相容（ADR 0008 §決定 3 的理由只適用有舊版的平台）。
- iTunes lookup：`com.personal.fmp`、`com.personal.fmp.dev` 都是 0 筆（實測），所以 App Store 上沒有 app 佔用這兩個 id。

### App ID 是否要全域唯一

- Apple 的 App ID 是明確字串，一個 team 註冊後別的 team 不能再註冊同一個明確 id。Xcode 免費帳號第一次建置時會自動註冊（Automatic signing）。若已被別人註冊，Xcode 會報「bundle identifier is not available，請改成唯一字串」（這是 Apple 開發者的一般經驗；**我沒有在本機測，因為註冊 App ID 會改動帳號狀態**，也沒找到官方頁面的逐字說明）。
- 因為 `com.personal.fmp` 只是通用的 `com.<人>.<app>` 命名，撞名機率不能排除，但**無法在不註冊的前提下確認**。
- 要付費帳號時，同樣是第一次註冊先搶先贏，差別只在註冊後這個 id 專屬於你的 team。
- 影響 `app/AGENTS.md` § App 身分：若 `com.personal.fmp` 註冊失敗，才需要換（例如加 team 前綴或自己的網域），而且：
  - 換 iOS 的 bundle id 會讓 iOS 與 Android／macOS 的 prod id 不同，要改 § App 身分的表、`test/identity/apple_identity_test.dart`（iOS 與 macOS 目前共用同一組預期值，原始碼，需查證）、ADR 0036 的 macOS 描述不受影響；
  - 換 id 是對外身分的變更，要另立 ADR（`app/AGENTS.md` 的開頭規定「改任何一項都要另立 ADR」）。
- 免費帳號的 10 個 App ID 額度：每次新增一個 id（prod、dev、之後的 Widget Extension）算一個；refresh 同一個 id 不另算（推論，SideStore 文件只說「每週最多 10 個不同 App」）。

## 4. CI 與發版

### 現況（原始碼，`.github/workflows/ci.yml`）

- `app-build-ios`（約 468-498 行）：`macos-latest`，`flutter build ios --flavor prod --release --no-codesign` 與 `--flavor dev --debug --no-codesign`；註解「不簽名（ADR 0009 §決定 9）：iOS 經 GitHub 發 IPA、由使用者側載時重簽」。
- 沒有 iOS 模擬器整合測試；沒有檢查 `fmp_quickjs` 的符號（macOS job 有，`ci.yml:448-455`）。
- `app-release.yml`（`build-macos` 在 270 行）沒有 iOS job；ADR 0022 §決定 3 附近寫「iOS 沒有發佈物，散佈方式由 iOS 平台任務決定」。

### 不簽名的 IPA（實測）

- `flutter build ipa --release --no-codesign` 在 Flutter 3.47.5 只產 `build/ios/archive/Runner.xcarchive`，輸出 "Codesigning disabled with --no-codesign, skipping IPA."，不產 IPA。
- 手動做：`flutter build ios --release --no-codesign` 之後
  ```
  mkdir -p out/Payload && cp -R build/ios/iphoneos/Runner.app out/Payload/ && (cd out && zip -qry ../fmp.ipa Payload)
  ```
  得到 IPA（探針專案 5.3 MB）；`codesign --verify` 回 "code object is not signed at all"。AltStore／SideStore 讀這種 IPA 後用使用者自己的 Apple ID 重簽（文件：SideStore 的 FAQ 說「resigns apps with your personal development certificate」）。
- flavor 版：`--flavor prod` 的 `.app` 在 `build/ios/iphoneos/` 還是 `Release-prod-iphoneos/` 之類，**我沒有用 FMP 的 flavor 跑，路徑不確定**，探針專案沒有 flavor。實作時以 `flutter build ios` 的輸出為準。
- 發版要不要產出未簽名 IPA：這是 ADR 0009 §決定 5 已經決定的方向（GitHub 發 IPA、側載）；技術上可行，`app-release.yml` 要新增 job 並在 release 資產清單加入。**這是設計決定，不在本報告範圍**。

### 模擬器整合測試（GitHub macOS runner）

- GitHub 的 macOS runner 有 Xcode 與 iOS 模擬器 runtime（repo 已用 `macos-latest`；`docs/adr/0036` 寫它目前是 `macos-26-arm64`、預設 Xcode 26.6）。
- 做法（Flutter 標準流程，**這份我沒有在 CI 實測，只在本機實測 `flutter build ios --simulator` 與 `simctl` 安裝／啟動**）：`xcrun simctl boot <udid>`（或先 `xcrun simctl create`）、`flutter devices` 取得裝置、`flutter test integration_test/install_search_play_test.dart -d <udid> --flavor dev`。
- 本機的模擬器建置與執行都走過（`flutter build ios --simulator --debug`，`simctl install`、`launch`），Flutter 的 release 模式不支援模擬器，所以整合測試只能是 debug／profile 外的 debug。
- 需要注意：`flutter_js` 的 `VALID_ARCHS[sdk=iphonesimulator*] = x86_64`（見 plugin-runtime-ios.md）；`macos-latest` 是 arm64，本機 Xcode 27.1 實測沒有受影響。

## 5. 建議：免費 vs 付費，對「擁有者每天在 iPhone 上用」的影響

以下是比較，不是替擁有者決定。

### 免費 Personal Team + AltStore／SideStore

- 7 天重簽：要靠 SideStore 的 VPN 背景 refresh 或 AltServer（Mac 與 iPhone 同一個 WiFi）。refresh 失敗超過 7 天，App 無法啟動；這是日常使用最大的風險（文件）。
- 3 個 App 的額度：SideStore 自己 1 個、FMP prod 1 個、FMP Dev 1 個，剛好滿；任何別的側載 App、Live Activity 的 Widget Extension 都放不下（文件＋推論）。
- 能力：背景播放、Keychain、App Groups 都可以（文件、本機 profile 實測）；Push 與 ActivityKit 的 push 更新不行。
- 費用：0。IPA 散佈符合 ADR 0009 現行的決定。

### 付費 Developer Program（US$99／年）

- 長效 profile（一年，未在官方頁確認）：免日常 refresh；直接用 Xcode 或 `devicectl` 安裝即可；首次啟動要連 `ppq.apple.com`（文件）。
- TestFlight 內部測試：90 天 build，要每 90 天重傳（自動化需要 App Store Connect API key）；不需要重簽，但需要 App Store Connect 的 App 紀錄。
- 解除 3 App／10 App ID 限制；Push、ActivityKit push 可用。
- 對「發 IPA 給別人側載」沒有幫助：給別人側載的 IPA 仍然是未簽名重簽。付費帳號主要讓擁有者自己的使用變輕鬆。
- 與 macOS 的連動：ADR 0036 §決定 3 的更正說「M9 做應用內更新時再決定付費 Developer ID 或改存放方式」，iOS 的決定可以與它一起看。

### 對日常使用的實際差別

| | 免費 | 付費 |
|---|---|---|
| 一週之後 App 還能開 | 靠 refresh；失敗就不能開 | 一年（未在官方頁確認）或 TestFlight 90 天 |
| 同時裝 prod 與 dev | 可以，但 SideStore 加上去就滿 | 無限制（App ID 無 10 個上限；裝置 100 台） |
| 重簽用的電腦／網路 | 需要（AltServer 或 VPN） | 不需要 |
| 成本 | 0 | US$99／年 |

## 沒查到／不確定

- 付費帳號 development／ad hoc profile 的效期數字：Apple 的幾個說明頁沒有明寫（grep 過 devices-overview、provisioning-profile-updates、create-a-development-provisioning-profile），我沒有照記憶下結論，標「未確認」。
- TestFlight 內部測試是否一律免送審、與 App Review Guideline 5.2.3 的關係：頁面只寫外部測試第一個 build 要送審。
- 免費帳號 Live Activity／Widget Extension 實際會不會被擋、算不算 3 個 App：沒有實測。
- `com.personal.fmp` 是否已被別人註冊：無法在不註冊的前提下確認；App Store 上沒有此 id（iTunes lookup 0 筆）。
- 沒做的事：沒碰實體 iPhone、沒安裝、沒改 Xcode 帳號設定、沒註冊 App ID、沒在 GitHub runner 實測。
- AltStore／SideStore 2026 年的行為：我只讀了 SideStore FAQ 與 AltStore 疑難排解兩頁，沒有查最新版本的重大變更（例如 iOS 27 的限制）。

## Related Specs

- `docs/adr/0009-platform-layer-with-declared-capabilities.md` §決定 5（iOS 散佈）、§決定 9（CI）
- `docs/adr/0022-release-and-in-app-update.md` §決定 3（iOS 沒有發佈物）
- `docs/adr/0036-macos-platform.md` §決定 3（憑證與簽章）
- `app/AGENTS.md` § App 身分、§ 發版
- `.trellis/tasks/archive/2026-11/10-28-macos-platform/research/`（範本）
