# 研究：平台商店政策限制與同類 Flutter 播放器的平台層架構

> 對應 `.trellis/tasks/09-27-design-platform` 的研究第 2、3 點。
> 查證方式：tavily-search／WebFetch 對官方或權威來源；同類專案透過
> `gh api`／raw GitHub 直接讀 `pubspec.yaml` 與原始碼目錄。查不到的一律
> 寫「查不到」，推論一律標「推測」。查證時間 2026-09-27（政策類內容請注意
> 官方頁面隨時可能更新，之後設計階段落地前建議重新核對一次日期）。

---

## 第 2 點：平台政策限制

### 2.1 iOS 側載（AltStore／SideStore）

**免費 Apple ID 簽名的硬性限制（事實）**：

- 憑證 **7 天**到期，須重新簽署；
- 免費帳號一次最多 **3 個** App 保持已簽署狀態（AltStore 本身也算一個
  名額）；
- 一週內最多能註冊 **10 個** App ID。

來源：SideStore 官方文件 FAQ
`https://docs.sidestore.io/docs/faq`（原文：「If using a free Apple
Account, SideStore can only install 3 apps (including itself) at a
time. Additionally, only 10 different apps may be installed in a
week.」；「Apple only allows 3 apps to be installed using a free Apple
Developer account.」）。

**付費 Apple Developer Program（$99/年）的差異（事實）**：憑證效期延長為
**365 天**，且解除 3-App 名額限制。同一份 SideStore FAQ 原文：「To
remove this restriction (and also get a 365 day expiry), you can pay
for a $99/year Apple Developer account.」

**繞過限制的手法（了解即可，不建議作為 FMP 的正式支援路徑）**：
LiveContainer 或針對特定舊版 iOS（18 db5/18.0.1 以下）的 SparseRestore
漏洞可繞過 3-App 限制，但**繞不過** 10 個 App ID／週的限制，且屬於利用
系統漏洞，不是官方支援的機制，不建議寫進 FMP 的設計依據裡。來源同上
SideStore FAQ。

**EU DMA 帶來的替代路徑（事實，隨時間演進中，需留意日期）**：

- 歐盟《數位市場法》（DMA）自 2024 年起強制 Apple 在歐盟境內開放
  第三方應用市集與網頁直接分發（Web Distribution）。
- 截至 2026-01-01，Apple 已將歐盟合規條款統一為：原本每次安裝
  0.5 歐元的 Core Technology Fee 取消，改為透過替代市集分發時收取
  **5% 固定抽成**。來源：
  `https://www.buildmvpfast.com/blog/eu-dma-digital-markets-act-app-store-sideloading-mobile-2026`
  （二手分析文章，非 Apple 官方一手來源，但內容與 Apple 官方公告方向
  一致，列為輔助佐證）。
- Apple 官方一手來源確認替代市集資格持續擴大：`https://developer.apple.com/support/apps-in-the-eu`
  原文：「Starting October 1, 2026, developers who meet at least one
  of the following criteria will be eligible to operate an alternative
  app marketplace」，並提到 2026 秋季會更新 EU 地區的 App 安裝體驗
  （安裝替代市集/App 時的系統確認流程）。
- **AltStore 已支援「初次設定後不需電腦」的裝置端側載**（事實，來源
  `https://www.buildmvpfast.com/blog/eu-dma-digital-markets-act-app-store-sideloading-mobile-2026`：
  「AltStore recently shipped on-device sideloading that works without
  a computer after the initial setup.」）——這代表在歐盟地區，側載的
  操作門檻已經比「電腦上跑 AltServer、手機和電腦要同 Wi-Fi」的傳統模式
  低很多，但**免費開發者帳號的 3-App／7-天限制本身沒有因為 DMA 而解除**
  （同來源原文：「Apple restricts free developer accounts to 3
  sideloaded apps at a time」）。
- 地區限制與跨區使用（事實）：離開已授權地區後，已安裝的替代市集
  App 有最多 **30 天**的寬限期仍可開啟使用，但無法安裝新 App 或更新
  既有側載 App，直到使用者返回受支援地區。來源：
  `https://staging.advance-he.org/ios-alternative-app-store-1vab.html`
  （二手整理文章，內容與 Apple 官方對地區偵測機制的描述方向一致，但
  非一手來源，列為輔助佐證，正式落地前建議直接查 Apple 官方文件核實
  30 天這個確切天數）。
- 替代市集本身的存續风险（事實案例）：MacPaw 的 Setapp Mobile 已於
  **2026-02-16** 在歐盟停止營運，官方說法是「業務條款仍在演變且複雜，
  不符合 Setapp 的商業模式」。來源：
  `https://techcrunch.com/2026/02/22/move-over-apple-meet-the-alternative-app-stores-available-in-the-eu-and-elsewhere`
  ——這說明依賴第三方替代市集作為 FMP iOS 分發管道本身帶有「市集可能
  說關就關」的風險，不是一勞永逸的解法。

**結論**：FMP 若要在 iOS 提供側載版本，免費 Apple ID 路線對「持續使用」
不友善（7 天要手動/背景重簽，且與其他側載 App 共用 3 個名額），付費
開發者帳號（年費 $99）是唯一能拿掉這兩個限制的正式路徑；EU DMA
替代市集是另一條路，但只在歐盟地區有效、政策仍在 2026 年持續演進中
（10 月 1 日還有新一輪資格開放），且已有替代市集中途關門的先例，
不宜當作長期穩定的唯一分發管道。

### 2.2 iOS 背景播放（Background Audio）

**必要設定（事實）**：Xcode 的 Background Modes capability 需要勾選
「Audio, AirPlay, and Picture in Picture」，對應在 `Info.plist` 寫入
`UIBackgroundModes` 陣列並含 `audio` 值。來源：Apple 官方文件
`https://developer.apple.com/documentation/xcode/configuring-background-execution-modes`。

**審核風險（事實，有多個開發者踩雷案例佐證）**：宣告了 `audio` 這個
background mode，但**實際上沒有持續播放聲音的功能**，會被 Apple 審核
以 **Guideline 2.5.4（Performance — Software Requirements）** 拒絕，
理由是「declares support for audio in the UIBackgroundModes key... but
did not include features that require persistent audio」。來源案例：
`https://devforum.zoom.us/t/ios-app-was-rejected-from-apple-appstore/37734`、
`https://community.appinventor.mit.edu/t/audio-in-the-uibackgroundmodes-key-in-your-info-plis/113744`。

**結論**：FMP 是音樂播放器，背景持續播放本來就是核心功能，宣告
`UIBackgroundModes: audio` 沒有 2.5.4 風險；但如果設計上出現「背景時
播放器實際被系統暫停」的路徑（例如某些串流來源在背景會斷線），要注意
這反而會製造審核風險，不是單純「加個 Info.plist key」就結束。

### 2.3 App Store 審核指引：下載第三方內容（YouTube 類）條款

**逐字核對現行 Apple 官方指引頁面**（來源：
`https://developer.apple.com/app-store/review/guidelines`，2026-09-27
查證版本）：

- **5.2.3 Audio/Video Downloading**：「Apps should not facilitate
  illegal file sharing or include the ability to save, convert, or
  download media from third-party sources (e.g. Apple Music, YouTube,
  SoundCloud, Vimeo, etc.) without explicit authorization from those
  sources. Streaming of audio/video content may also violate Terms of
  Use, so be sure to check before your app accesses those services.
  Authorization must be provided upon request.」
- **5.2.2 Third-Party Sites/Services**：「If your app uses, accesses,
  monetizes access to, or displays content from a third-party service,
  ensure that you are specifically permitted to do so under the
  service's terms of use. Authorization must be provided upon
  request.」
- **2.5.2**：現行版本文字為「Apps should be self-contained in their
  bundles, and may not read or write data outside the designated
  container area, nor may they download, install, or execute code
  which introduces or changes features or functionality of the app,
  including other apps. Educational apps designed to teach, develop,
  or allow students to test executable code may, in limited
  circumstances, download code provided that such code is not used
  for other purposes.」——這條規範的是「下載可執行程式碼」，跟 FMP
  下載媒體檔案（音訊）是不同的行為類別，不直接適用，但方向上共通點是
  「Apple 對『App 執行期動態取得外部內容/程式碼』一律要求明確授權或
  限縮用途」。

**FMP 的實際處境（推測，非官方逐字判定）**：FMP 播放/下載 Bilibili、
YouTube、網易雲音樂的內容，若要上 App Store，5.2.3 與 5.2.2
是最直接相關的兩條——**串流播放**本身已經處於「使用第三方服務內容」
的灰色地帶（要看該服務 ToS 是否允許第三方 client 存取，這是各來源
自己的服務條款問題，不是 Apple 一方能豁免的），**下載並保存到本機**
則幾乎確定會被視為 5.2.3 所指的「download media from third-party
sources... without explicit authorization」，這個問題不是「换個
措辭」或「加個免責聲明」能解決，是 FMP 現有下載功能在 iOS App Store
分發模式下的結構性衝突（此為推測，實際判定以 Apple 審核當下為準，
但風險本身可從指引原文直接讀出，不是無中生有的推測）。

### 2.4 macOS 未公證（unnotarized）App 的安裝體驗與公證需求

**公證需要什麼（事實）**：需要 **Apple Developer Program 付費帳號**
（Developer ID 憑證），用 Developer ID 簽署後透過 `notarytool`
（`altool` 已於 2023-11-01 起停止接受上傳）送交 Apple 公證服務做
自動安全掃描，通過後取得票證（ticket），讓 Gatekeeper 在使用者
第一次執行/安裝時確認「已通過公證」。來源：
`https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution`、
`https://developer.apple.com/developer-id`。

**未公證的使用者體驗（事實，且近年變嚴）**：

- 傳統上使用者可以用「按住 Control 點兩下開啟」繞過 Gatekeeper 的
  警告；但 **macOS Sequoia 起這條路徑被拿掉**，使用者必須改到
  「系統設定 > 隱私權與安全性」裡手動允許該軟體執行。來源 Apple
  官方新聞稿：`https://developer.apple.com/news?id=saqachfa`
  （原文：「In macOS Sequoia, users will no longer be able to
  Control-click to override Gatekeeper... They'll need to visit
  System Settings > Privacy & Security to review security
  information for software before allowing it to run.」）。
- 未公證但已簽署（或完全未簽署）的 App，Gatekeeper 會在啟動對話框中
  顯示描述性警告資訊，幫助使用者判斷是否要繼續執行；公證本身對終端
  使用者是「近乎無感」的背景流程，差別主要體現在這個警告訊息與
  Sequoia 之後那個多一步的系統設定操作。來源同上
  `notarizing-macos-software-before-distribution` 文件。

**結論**：FMP 若要在 macOS 上以「非 App Store」形式分發，公證不是
必須（Gatekeeper 仍可被使用者手動放行），但 Sequoia 之後的手動放行
流程比以前繁瑣（多一層系統設定），對一般使用者是明顯的安裝摩擦；
要做到「開箱能雙擊執行不嚇到使用者」，公證加 Developer ID 簽署
（年費 $99 的 Apple Developer Program）是目前唯一官方認可的路徑。

### 2.5 Google Play 對 `MANAGE_EXTERNAL_STORAGE` 的限制

**官方允許用途（事實，逐字節錄自 Google 官方文件）**：

> "For apps requesting access to the All files access permission,
> intended and permitted use includes file managers, backup and
> restore apps, anti-virus apps, and document management apps."

來源：Play Console 官方說明
`https://support.google.com/googleplay/android-developer/answer/10467955`；
Android 官方開發文件同樣列出這幾類：檔案管理、備份還原、防毒、文件
管理，且需求必須「與 App 核心功能直接相關」。來源：
`https://developer.android.com/training/data-storage/manage-all-files`。

**明確不允許的用途（事實）**：官方文件明列「Media Files access」與
「Any File selection activity where the user manually selects
individual files」是**無效用途**，這兩種情境應該改用 Storage Access
Framework 或 MediaStore API，而不是申請 `MANAGE_EXTERNAL_STORAGE`。
來源同 `support.google.com` 上引文件。

**審核流程（事實）**：宣告此權限且目標 API 為 Android 11+
的 App，Google Play 要求開發者完成 **Permissions Declaration Form**
並取得 Google 核准才能上架；Android Studio 本身也會對宣告此權限的
App 顯示 lint 警告，提醒這項政策限制。來源：
`https://developer.android.com/training/data-storage/manage-all-files`。

**結論**：FMP 的下載/儲存功能如果只是「把音訊檔案存到 App 自己的
下載目錄」，屬於 App-specific storage，根本不需要
`MANAGE_EXTERNAL_STORAGE`；只有當設計要求「讓使用者自由選擇任意
外部目錄存放下載檔案」時才會踩到這個權限，且即使申請也大機率不符合
官方列出的允許用途（FMP 不是檔案管理員/防毒/備份還原/文件管理
App），送審被拒的風險偏高。這對「檔案選取/應用程式目錄」的設計
方向是明確訊號：優先走 Storage Access Framework（透過 `file_picker`
之類套件底層走 SAF）或 App 專屬目錄（`path_provider`），不要設計成
需要 `MANAGE_EXTERNAL_STORAGE` 的形態。

### 2.6 Linux 打包格式的應用內自我更新可行性

| 格式 | 能否應用內自我更新 | 依據 |
|---|---|---|
| **AppImage** | **可以**，透過 `AppImageUpdate` 搭配 `zsync` 協定做差量更新，只下載檔案中真正變動的部分。更新資訊（update information）在打包時用 `appimagetool -u` 內嵌進 AppImage 本身。 | AppImage 官方打包指南 `https://docs.appimage.org/packaging-guide/optional/updates.html`；`appimage-builder` 官方文件 `https://appimage-builder.readthedocs.io/en/latest/advanced/updates.html`；`https://appimage.github.io/AppImageUpdate`（AppImageUpdate 官方頁面，甚至 AppImageUpdate 自己也是用同一套機制自我更新）。 |
| **Flatpak** | **官方立場是「App 不應該自己做更新」**，更新這件事是 Flatpak 執行環境本身的職責（`flatpak update`），由使用者的桌面環境（如 GNOME Software／KDE Discover）或排程任務（systemd timer）觸發。多個社群討論串證實 Flatpak **沒有內建的「App 自動更新」機制**，需要使用者手動或靠桌面環境的排程功能。 | `https://www.jwillikers.com/automate-flatpak-updates-with-systemd`（原文：「Flatpak doesn't provide an auto-update mechanism but instead leaves this up to software apps」——注意這裡的語境是指「Flatpak 平台不會主動幫你排程」，而不是「App 可以自己實作更新」；實務上 Flatpak sandbox 本身的權限模型也不鼓勵 App 繞過 Flatpak 機制自己下載並替換自身執行檔）；Flathub 社群討論串進一步說明「an app bundles its dependencies... if one of these dependencies get updated you get a flatpak update」，更新的決策權在 manifest／repo 層級，不是 App 執行期自己觸發。來源：`https://discourse.flathub.org/t/flatpak-update-problem-again/10115`。 |
| **deb** | **不能**，`.deb` 格式本身沒有自我更新機制，更新完全依賴 `apt`/`dpkg` 或第三方封裝的倉庫管理工具（如 `deb-get`）去重新整理套件索引並安裝新版。 | Debian 官方文件 `https://www.debian.org/doc/manuals/debian-faq/pkgtools.en.html`（`apt update`／`apt upgrade` 的標準流程）；`deb-get` 專案本身的存在（`https://github.com/wimpysworld/deb-get`）恰好反向證明：正因為原生 `.deb` 生態系沒有「App 自己更新自己」的機制，才需要這類第三方工具去統一管理「透過 GitHub 或直接下載發布的 `.deb` 套件」的更新流程。 |

**結論**：三種 Linux 封裝格式裡，**只有 AppImage 適合做「應用內
自我更新」**這個 FMP 設計問題（audit §7 開放問題 #4）的候選；Flatpak
理論上技術上可行但違反平台慣例（使用者與桌面環境預期「更新交給
Flatpak 系統本身」，App 自己動手改變安裝內容甚至可能被 sandbox
權限擋下）；deb 完全沒有這個能力，若要支援 `.deb` 分發，更新只能
交給使用者手動下載新版或維護自己的 apt 倉庫（等於要自己維運一個
套件源，複雜度遠高於單純做「應用內檢查更新」）。

---

## 第 3 點：同類 Flutter 音樂播放器的平台層架構

四個對照專案：Spotube（`KRTirtho/spotube`，近期已轉移組織至
`team-spotube/spotube`）、Harmony Music（`anandnet/Harmony-Music`）、
Finamp（已從 `jmshrv/finamp` 轉移到 `finamp-app/finamp`，預設分支是
`redesign` 而非 `master`）、Namida（`namidaco/namida`，本身即針對
Android **與桌面**，並非行動端專屬）。

### 3.1 依賴清單比較（逐字取自各自 `pubspec.yaml`）

| 能力 | Spotube | Harmony Music | Finamp | Namida |
|---|---|---|---|---|
| 系統匣 | `tray_manager: ^0.5.0` | `tray_manager: ^0.2.3` | （未見於 pubspec，查不到是否有此功能） | `tray_manager`（**自己 fork**：`https://github.com/MSOB7YY/tray_manager`，非 pub.dev 版本） |
| 視窗管理 | `window_manager: ^0.4.3` | `window_manager: ^0.4.2` | `window_manager: ^0.5.1` | `window_manager: ^0.5.0` |
| 單一實例 | 查不到（pubspec 未見專門套件，可能走自訂或未實作） | 查不到 | 查不到 | **自己 fork**：`windows_single_instance`（`https://github.com/MSOB7YY/flutter_windows_single_instance`） |
| 系統媒體控制（Android/iOS/macOS） | `audio_service: ^0.18.13` | `audio_service: ^0.18.17` | `audio_service: ^0.18.18` + `audio_service_platform_interface: ^0.1.3` | `audio_service`（**自己 fork**：`https://github.com/MSOB7YY/audio_service`） |
| 系統媒體控制（Linux MPRIS） | `audio_service_mpris: ^0.2.0` | `audio_service_mpris: ^0.1.5` | `audio_service_mpris: ^0.2.0` | `anni_mpris_service: ^0.1.0`（pub.dev 官方版本，而非自己 fork——與其他能力大量自 fork 的風格不同，值得注意） |
| 系統媒體控制（Windows SMTC） | `smtc_windows: ^1.1.0` | `smtc_windows: ^0.1.2`（明顯落後版本） | `smtc_windows`（**用本地 path**：`packages/smtc_windows/`，pubspec 註解說明是因為對某些相依套件的版本鎖定需求） | `smtc_windows`（**用本地 path**：`packages/smtc_windows`） |
| 音訊引擎 | `media_kit`（**全部改用本地 path**：`media_kit`/`libs/android/`/`libs/ios/`/`libs/macos/`/`libs/windows/`/`libs/linux/`，等於自己 vendor 了一整份 media_kit 家族而非直接吃 pub.dev 版本） | `just_audio: ^0.9.46` + `just_audio_media_kit`（**自己 fork**：`https://github.com/anandnet/just_audio_media_kit.git`，用 just_audio 的介面包一層 media_kit 當桌面後端） | `just_audio`（**自己 fork**：`https://github.com/LennartEnns/just_audio_fork.git`，pubspec 註解明講原因：等官方 PR #1555 合併前的暫時替代）+ `just_audio_media_kit`（另一個 fork：`https://github.com/Komodo5197/just_audio_media_kit.git`）+ `media_kit_libs_linux`／`media_kit_libs_windows_audio` | `media_kit`（本地 path）+ `media_kit_video`／`media_kit_libs_linux`／`media_kit_libs_macos_video`／`media_kit_libs_windows_video`（官方 pub.dev 版本）+ `just_audio`（**自己 fork**：`https://github.com/MSOB7YY/just_audio`） |
| 登入 WebView | `flutter_inappwebview: ^6.1.5` + `desktop_webview_window`（**用本地 path**：`packages/desktop_webview_window`，等於也自己維護了一份 fork） | 查不到 | 查不到 | 查不到（Namida 本身不含帳號登入類來源，屬性質不同的播放器，此項目不適用，非查證疏漏） |
| 網路狀態 | 查不到（未見 `connectivity_plus`） | 查不到 | `connectivity_plus: ^7.0.0` | `connectivity_plus: ^7.0.0` |

**觀察到的共通模式（事實，非推測）**：**四個專案沒有一個是「純吃
pub.dev 發布版本」**——只要牽涉到桌面平台的音訊引擎（`media_kit`／
`just_audio`）、Windows SMTC（`smtc_windows`）或更冷門的桌面能力，
四個專案裡有三個（Spotube、Finamp、Namida）都改用 **本地 path 依賴
或自己 fork 的 git 依賴**，而不是直接引用 pub.dev 上的版本。這反映
一個現實：pub.dev 生態系裡「桌面平台整合類」套件的發布節奏，追不上
這些專案自己需要的修補速度或客製化需求，因此普遍策略是「先蹲點在
一個能動的 fork/vendor 版本上，而不是被上游的發布週期綁住」。這對
FMP 的設計啟示是：規劃桌面平台整合套件時，要預先假設「未來很可能
需要 fork 或 vendor 某些套件」，不能假設 pub.dev 上的版本會一直
剛好符合需求，設計上應該預留「套件來源可以是 git/path 而非純
pub.dev version constraint」的彈性（這在 pubspec.yaml 語法上本來就
支援，只是要在專案慣例/CI 裡承認並規範這種情況怎麽處理，例如要不要
鎖 commit hash、要不要同時追蹤上游 PR 進度）。

### 3.2 平台差異程式碼的組織方式：集中 vs. 散落

**Spotube**：程式碼庫內找到明確的集中化檔案（來源：
`gh api repos/KRTirtho/spotube/git/trees/master?recursive=true`
逐一列出的路徑）：

- `lib/utils/platform.dart` —— 集中定義 `kIsDesktop`／`kIsMobile`／
  `kIsFlatpak` 之類的平台旗標常數，供全專案 import 使用（非
  逐檔案重複寫 `Platform.isX`）。
- `lib/services/wm_tools/wm_tools.dart` —— 把 `window_manager` 的
  操作包一層自己的介面。
- `lib/provider/tray_manager/tray_manager.dart` +
  `lib/provider/tray_manager/tray_menu.dart` —— 系統匣邏輯獨立成
  一個 provider 模組，不是散落在 UI 頁面裡直接呼叫
  `TrayManager.instance`。
- `lib/services/audio_services/{audio_services.dart,
  mobile_audio_service.dart, windows_audio_service.dart}` ——
  音訊服務依平台（行動端 vs. Windows）拆成不同檔案，但共用同一個
  上層抽象檔案 `audio_services.dart` 做選擇分派。

**Namida**（四個對照專案裡集中化程度最徹底、最值得 FMP 直接參考的
一個）：整個 `lib/controller/platform/` 目錄本身就是一個「平台層」，
每個平台會有差異的能力各自一個子目錄，命名慣例統一為
`<capability>.dart`（對外的統一介面/工廠）+ `<capability>_base.dart`
（共用抽象定義）+ `<capability>_<platform>.dart`（各平台實作），總共
涵蓋：`app_single_instance`、`ffmpeg_executer`、`home_widgets`、
`namida_channel`（原生 MethodChannel 封裝）、`namida_storage`、
`permission_manager`、`shortcuts_manager`、`smtc_manager`、
`tags_extractor`、`tray_manager`、`window_manager`、`zip_manager`，
共 12 個能力模組。來源：
`gh api repos/namidaco/namida/git/trees/main?recursive=true`。

實際機制（讀取
`https://raw.githubusercontent.com/namidaco/namida/main/lib/controller/platform/base.dart`
與同目錄下 `tray_manager/tray_manager.dart`、
`namida_channel/namida_channel.dart` 原始碼確認）：

- `base.dart` 定義一個泛型工廠 `NamidaPlatformBuilder`，核心方法
  `init<T>({required android, required windows, linux, ios, macos})`
  內部用 `switch (defaultTargetPlatform) { TargetPlatform.android =>
  android(), ... }` 做分派，未支援的平台丟
  `UnimplementedError()`；另有 `initValue<T>` 處理「值」而非
  「建構函式」的情境，並用一個 sentinel object（`_unsupportedPlatform`）
  去區分「這個平台回傳 null」跟「這個平台根本不支援」兩種語意，避免
  用 `null` 混用造成歧義。
- 各能力模組的「對外介面檔」（如 `tray_manager.dart`、
  `namida_channel.dart`）本身**不是**用 Dart 語言層級的條件匯入
  （`if (dart.library.io)` 那種），而是用 **`part`/`part of`**
  把 `_base.dart`、`_android.dart`、`_linux.dart`、`_windows.dart`
  等檔案全部合併成同一個檔案的邏輯單元，執行期再靠
  `NamidaPlatformBuilder.init(...)` 動態決定要建構哪個實作類別。
  這代表**所有平台的實作程式碼都會被一起編譯進最終產物**（不像
  條件匯入那樣在編譯期就把不相關平台的程式碼排除掉），换來的好處是
  程式碼閱讀動線更直覺（同一個能力的所有平台變體都在同一個邏輯檔案
  群組裡，`part of` 語法上要求彼此可以互相直接引用型別而不用
  import），代價是理論上執行檔會包含用不到的其他平台程式碼（對
  Dart/Flutter 這種每個平台本來就是分開建置產物的情況，這個代價
  在實務上通常可忽略——Windows 建置產物本來就不會真的執行到
  Android 分支的程式碼，只是原始碼/中介表示層次上都在）。

**Finamp**：只找到一個集中化訊號——`lib/utils/platform_helper.dart`
與 `lib/services/audio_service_smtc.dart`（來源：
`gh api repos/finamp-app/finamp/git/trees/redesign?recursive=true`），
規模遠不如 Namida，比較接近「有一個統一的平台判斷 helper，但沒有
像 Namida 那樣每個能力都獨立成一個目錄」的中間型態。

**Harmony Music**：本次查證範圍內（僅 `pubspec.yaml` 逐項比對）
未進一步深入其 `lib/` 目錄結構，**查不到**其平台差異程式碼是集中
還是散落——受限於研究時間，這個專案只完成依賴清單比對，架構層面
留待需要時再補查。

### 3.3 結論：共通模式與對 FMP 的啟示

1. **沒有任何一個對照專案是「純用 `Platform.isX` 散落各處」**——
   至少都有一個集中的平台旗標檔案（Spotube 的
   `lib/utils/platform.dart`、Finamp 的 `platform_helper.dart`），
   程度較深的（Namida）則是把每個「會隨平台變化的能力」都獨立成
   一個目錄，用同一種「`_base.dart` + 各平台實作 + 一個工廠函式」
   的樣板去組織，這與 Flutter 官方文件裡 federated plugin
   「共用抽象 + 各平台各自實作」的精神是一致的（見
   `platform-packages.md` 第 14 節），只是 Namida 是在應用層自己
   重造了一套更輕量的版本，而不是真的發布成獨立 pub.dev 套件。
2. **音訊/桌面整合類套件普遍要接受「fork 或 vendor」**，不是
   FMP 現況（audit 文件觀察到的三種平台判斷風格並存）特有的問題，
   而是這個生態系普遍的現實。
3. 對 audit §7 開放問題 #11（是否該把三種平台判斷風格收斂成統一的
   capability 物件）：Namida 的 `NamidaPlatformBuilder` 模式提供了
   一個具體、已經在生產環境跑過的參考答案——**不是**做一個龐大的
   「單一 capabilities 物件」把所有能力塞進同一個介面，而是「每個
   能力各自一個小模組，共用同一套建構分派慣例（同名工廠函式/相同
   目錄命名規則）」，讓新增一個平台差異點的成本是「照現有模式加一個
   子目錄」，而不是「去改一個中央大物件的介面」。

---

## 待補查項（誠實列出）

- Harmony Music 的 `lib/` 目錄結構（是否集中化平台判斷）——本次未
  執行，查不到。
- Spotube 是否有 `connectivity_plus` 或等價的網路狀態偵測——pubspec
  未見，查不到是否用其他方式判斷網路狀態（例如直接依賴 `dio` 的
  請求失敗來間接判斷）。
- EU DMA replacement marketplace 的 30 天跨區寬限期，來源為二手
  整理文章而非 Apple 一手文件，正式寫入 design.md 前建議重新以
  `developer.apple.com/support/apps-in-the-eu` 或其連結的官方頁面
  核對確切天數與生效條件。
