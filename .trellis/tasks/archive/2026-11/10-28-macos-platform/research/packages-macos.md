# Research: macOS 平台所需套件調查（釘版本）

- **Query**: FMP `app/` 要在 macOS（Apple Silicon、macOS 27、App Sandbox、未簽章／ad-hoc 本機建置、發版為未公證 zip、無付費開發者帳號）上跑，逐一調查 `pubspec.lock` 釘的套件版本在 macOS 的支援、entitlement、已知問題。
- **Scope**: mixed（pub cache 內的原始碼 + 本機實測 + pub.dev / GitHub issue）
- **Date**: 2026-10-28
- **環境**: Flutter 3.47.5（engine af7e796e16）、Xcode 27.1、macOS 27.0.1、Apple Silicon。
- **方法說明**: 原始碼結論來自 `~/.pub-cache/hosted/pub.dev/<pkg>-<ver>/`（即鎖定版本的實際內容）。凡標「實測」的，都是我在 scratchpad 寫小型 Swift 程式，以 ad-hoc 簽章（`codesign -s -`）加 App Sandbox entitlement 在本機實跑的結果；測試程式在 `<暫存目錄>/`（`av/`、`kc/`、`rl/`），不在 repo 內。沒有改動任何 repo 檔案。

## 0. 釘版本與 macOS 實作一覽

| 套件 | `pubspec.lock` 版本 | macOS 實作 | 原生建置方式 | macOS 最低版本（套件宣告） |
|---|---|---|---|---|
| just_audio | 0.10.6 | 內建（共用 darwin 原始碼，AVQueuePlayer） | SPM（`darwin/just_audio/Package.swift`） | 10.14 |
| audio_service | 0.18.19 | 內建（共用 darwin） | SPM | 10.14（README 寫 10.12.2） |
| audio_session | 0.2.4 | 內建 | SPM | 10.14 |
| flutter_secure_storage | 11.2.0 → `flutter_secure_storage_darwin` 0.4.3 | darwin 子套件 | SPM | 10.14 |
| flutter_inappwebview | 6.2.0-beta.3 → 預設 `flutter_inappwebview_macos` 1.2.0-beta.3 | **本 repo 以 `flutter_inappwebview_macos_stub` 取代（純 Dart，不編原生碼）** | （真實作有 SPM；stub 無原生） | 真實作 10.14 |
| window_manager | 0.5.2（+ `screen_retriever_macos` 0.2.2） | 內建 | SPM | 10.15（screen_retriever 10.14） |
| file_picker | 13.1.0 → `file_picker_darwin` 2.1.3 | darwin 子套件 | SPM | 10.13 |
| share_plus | 13.3.1 | 內建 | SPM | 10.15 |
| url_launcher | 6.3.3 → `url_launcher_macos` 3.2.6 | 子套件 | SPM | 10.15 |
| connectivity_plus | 7.3.1 | 內建 | SPM | 10.15 |
| path_provider | 2.1.6 → `path_provider_foundation` 2.6.0 | 純 Dart + FFI 呼叫 Foundation（`native_build:false`） | 無原生外掛（用 `objective_c` 9.5.0 的 FFI） | 10.15（CHANGELOG 2.4.3） |
| package_info_plus | 10.2.2 | 內建 | SPM | 10.15 |
| isar_community_flutter_libs | 3.3.2 | 內建（vendored dylib） | **CocoaPods（無 Package.swift）** | podspec 10.11；dylib arm64 `minos 11.0` |
| media_kit | 1.2.6 | **無 macOS 原生外掛**（純 Dart + 執行時載 libmpv） | 無 | — |
| media_kit_libs_windows_audio | 1.0.9 | 只有 windows | 無 | — |
| flutter_js | 0.8.7 | **macOS 只有一個空殼 Swift 外掛，沒有 QuickJS 原生庫** | CocoaPods（只有 podspec） | podspec 10.11 |

- 專案 `MACOSX_DEPLOYMENT_TARGET = 12.0`（`app/macos/Runner.xcodeproj/project.pbxproj:555,650,734`；Flutter 3.47 範本 Podfile 也是 `platform :osx, '12.0'`，`~/development/flutter/packages/flutter_tools/templates/cocoapods/Podfile-macos:1`）。高於所有套件宣告的最低版本，沒有部署版本衝突。
- 各套件最新版（pub.dev API，2026-10-28）：just_audio 0.10.6（同）、audio_service 0.18.19（同）、flutter_secure_storage 11.2.0（同）、window_manager 0.5.2（同）、file_picker 13.3.0（釘 13.1.0）、share_plus 13.3.1（同）、connectivity_plus 7.3.2（釘 7.3.1）、isar_community_flutter_libs 3.4.1（釘 3.3.2，刻意釘死）、flutter_inappwebview_macos 穩定版 1.1.2、最新 1.2.0-beta.3（同釘）。

---

## 1. just_audio 0.10.6（macOS：yes）

### 1.1 實作與最低版本
- macOS 用 `AVQueuePlayer`（`darwin/just_audio/Sources/just_audio/AudioPlayer.m:25,670`）；`Package.swift` 與 podspec 都是 macOS 10.14。
- README 平台表（`just_audio-0.10.6/README.md:408-430`）：macOS 的 URL 讀取、request headers、HLS、gapless、playlists、clip、loop/shuffle 都是 yes；**DASH 在 iOS/macOS 為空白（不支援，指 DASH 的 `.mpd` manifest）**；pitch、skip silence、equalizer、volume boost 只有 Android。
- 需要的 entitlement（README `:296-301`）：`com.apple.security.network.client` 要加在 `DebugProfile.entitlements` 與 `Release.entitlements`。需要 `NSAppTransportSecurity` 的情況見 1.5。

### 1.2 自訂標頭怎麼做（本 App 的設定）
- `JustAudioBackend` 建構時傳 `useProxyForRequestHeaders: false`、`useLazyPreparation: false`（`app/lib/playback/backends/just_audio_backend.dart:21-26`），來源以 `AudioSource.uri(..., headers: ...)` 建立（`:290-292`）。
- `useProxyForRequestHeaders: false` 時，Apple 端不開本機 proxy，改在 `UriAudioSource.m:49-68` 把標頭放進 `AVURLAsset` 的 options：
  - 標頭只有一個且是 `User-Agent` 且 macOS ≥ 13：用公開 API `AVURLAssetHTTPUserAgentKey`；
  - 其他情況（我們有 Referer、User-Agent、Cookie 多個）：`assetOptions[@"AVURLAssetHTTPHeaderFieldsKey"] = _headers`。
- **`AVURLAssetHTTPHeaderFieldsKey` 不在公開 SDK 標頭裡**：在 `MacOSX27.0.sdk/.../AVFoundation.framework/Headers/` grep，只找到公開的 `AVURLAssetHTTPCookiesKey`（`AVAsset.h:577`）與 `AVURLAssetHTTPUserAgentKey`（`:614`）。just_audio README（`:115`）也自承這是未公開 API。
- `useProxyForRequestHeaders: true`（預設）時改走本機明文 HTTP proxy（`just_audio.dart:2735-2754`），需要 ATS 例外，且只有 Dart 端能改標頭；本 App 沒用它，所以**不需要為 proxy 加 `NSAllowsArbitraryLoads`**。
- 公開 issue：#470「HLS 標頭不遞迴套用」（open，2021 年起；那是 proxy 模式的限制，Dart 端 `HlsAudioSource` 文件寫 "headers are not applied recursively"）；#1245（open，locked）關於 `AVURLAssetHTTPUserAgentKey` 與 `AVURLAssetHTTPCookiesKey` 的討論，沒有結論；#747（open）iOS 鎖屏一段時間後帶標頭的來源行為異常（iOS 為主）。

### 1.3 實測：AVPlayer 能不能播（本機，ad-hoc + Sandbox + `network.client`）
測法：用 `AVAssetWriter`（`.mpeg4AppleHLS` profile）把一段 89.76 秒 AAC-LC 44.1kHz 立體聲切成 fMP4（init + 4 秒 moof/mdat），再組成各種形式，由 Python 伺服器（支援 Range，**必須**帶 `Referer: https://www.bilibili.com/`、自訂 `User-Agent`、`X-Test`、`Cookie: SESSDATA=abc` 才回 200，否則 403）提供；以 `AVURLAsset(options: [AVURLAssetHTTPHeaderFieldsKey: …])` 播放並 seek 到 60 秒。

| 案例 | 結果 |
|---|---|
| (a1) 單一 `.m4s` URL，ftyp+moov+多個 moof/mdat，**無 sidx**，HTTP Range | 播放、`duration=89.767`、seek 60 秒成功（位置 ≈61.9）；伺服器只看到 1 個請求 `Range: bytes=0-927436`，四個標頭都到 |
| (a2) 同上但**手工插入 `sidx`**（接近 Bilibili DASH 音訊的結構） | 同上，`duration=89.767`，seek 成功 |
| (b1) HLS，`#EXT-X-MAP` + fMP4 `.m4s` 分段，VOD（有 ENDLIST） | 播放；**playlist、init、每個分段請求都帶齊標頭**（0 個 403）；seek 成功 |
| (b2) 同上，live 形式（無 ENDLIST、無 PLAYLIST-TYPE） | 播放；playlist 會重載（4 次），所有請求標頭都到；`item.duration = NaN`，`seekableTimeRanges` 約 77 秒（見 1.6） |
| (b3) HLS，TS 分段（AAC-in-MPEG-TS，自己用 Python 封裝），VOD 與 live 形式 | 兩種都播放；所有請求標頭都到（VOD 25 個請求 0 失敗；live 15 個 0 失敗） |
| 不帶標頭 | 伺服器回 403，`AVPlayerItem.status = failed`（"You do not have permission…"），驗證測試確實檢查標頭 |
| (c) FLV | **未實測**（沒有可用的 FLV 樣本、也沒有 ffmpeg）。AVFoundation 不支援 FLV 容器是公認事實，但本次沒有用實驗確認 |

- **Content-Type 影響很大**：同一個 `sidx.m4s`，伺服器回 `audio/mp4` 或 `video/mp4` 都能播；回 `application/octet-stream`（副檔名仍是 `.m4s`）時 `item.status = failed`，錯誤 "Cannot Open"。just_audio README（`:313`）也寫 macOS 依賴伺服器的 `Content-Type`、`Content-Length`、Range。
- **Bilibili 真實 CDN 的 Content-Type、真實 DASH 音訊檔的結構／編碼沒有驗證**：匿名呼叫 `api.bilibili.com/x/web-interface/view` 直接回 412（反爬），拿不到真實音訊 URL。本實測的 fMP4 是我自己用 AVAssetWriter 產的 AAC-LC，sidx 是手工寫的；Bilibili 也提供 Dolby E-AC-3、FLAC 軌，這些在 AVPlayer 能否播沒有測。
- 沙箱要求（實測）：同一支程式，Sandbox 但**沒有** `com.apple.security.network.client` → 伺服器 0 個請求、`status=failed`（"The operation could not be completed"）；加上 `network.client` 才正常。

### 1.4 gapless／預載
- README 平台表 gapless 在 macOS 為 yes。實作是 `AVQueuePlayer`，每個項目是獨立的 `AVPlayerItem`（`UriAudioSource.m` 以每個來源各建 `AVURLAsset`+`IndexedPlayerItem`），標頭是**每個來源各自**放進該來源的 `AVURLAsset` options，下一首的標頭不依賴目前這首。
- App 設 `useLazyPreparation: false`（「第二個項目一接上就預備」）；macOS 上的實際預載時機與緩衝量（`preferredForwardBufferDuration` 預設 NSNull，`AudioPlayer.m:99-108`）**沒有實測**。
- 相關 issue：#877「DarwinLoadControl preferredForwardBufferDuration does not work properly in iOS」（open）。

### 1.5 ATS（App Transport Security）
- `Info.plist`（`app/macos/Runner/Info.plist`）目前沒有 `NSAppTransportSecurity`。
- 實測（Sandbox + `network.client`，ad-hoc）：`http://127.0.0.1` 與 `http://localhost` 的 AVPlayer 請求**不受 ATS 限制**（loopback 豁免）；`http://example.com/…`（網站可連）→ `status=failed`，底層錯誤 `NSOSStatusErrorDomain -1022`（`NSURLErrorAppTransportSecurityRequiresSecureConnection`）。**也就是 AVPlayer 在 macOS 同樣受 ATS 限制，明文 `http://` 音訊 URL（非 loopback）會失敗**，除非 Info.plist 加 ATS 例外。https URL 不受影響。
- 本 repo 目前有沒有來源會回傳 `http://` 音訊 URL 沒有查（不在本次範圍）。

### 1.6 已知 macOS 問題（just_audio）
- **#1599（open，2026-08-26）**：Apple silicon 上 MP3 的 `duration` 為 0、position 停在 0:00（根因：`UriAudioSource.m` 的 `duration` 在 `seekableTimeRanges.lastObject` 存在時就回傳它，即使它是 indefinite；`CMTimeGetSeconds(indefinite)=NaN`，`(int)NaN` 在 arm64 為 0，Dart 端 `just_audio.dart:673-683` 再把 position 夾到 0）。issue 內的測試環境是「iOS app on Apple silicon Mac」，M4A（AAC）、WAV、HLS 正常，只有 MP3 異常。
- **#1435（open）**：LockCachingAudioSource／多次轉址時 position、duration 為 0，同樣有 ARM macOS 的回報（x86 macOS 為 null、ARM 為 `Duration.zero`）。後續留言認為伺服器缺 `Content-Length`／`Content-Range`／206 或 MIME type 不對也會造成。
- **#903（open）**：iOS HLS 的 duration 不正確。我的 (b2)/(b3) live 實測：`item.duration=NaN`，但 `seekableTimeRanges` 有約 75–78 秒的視窗；`UriAudioSource.m:177-187` 優先回傳 seekable range 的 duration，所以 live HLS 會被回報成「視窗長度」而不是 null。（讀程式推論，未用 just_audio 本體在 macOS 實跑）
- 其他：#881（closed，M4A 在 iOS/macOS 不緩衝）。

### 1.7 對我們的意義
- 標頭機制（`AVURLAssetHTTPHeaderFieldsKey`）在 macOS 27 + Sandbox + ad-hoc 下**實測可行**，含 Cookie、Referer、UA，HLS 的 playlist／init／分段都帶標頭。它是未公開 key，Apple 沒有保證。
- Bilibili DASH 音訊（單一 `.m4s` + Range）的形式在 AVPlayer 可播，前提是 CDN 回的 Content-Type 不是 `application/octet-stream`；真實檔需上機實測（ADR 0018 `:76` 也這樣寫）。
- 直播 HLS：fMP4 與 TS 兩種都可播（本機合成樣本）。
- FLV：未驗證，預期不能播。
- 上面三個 duration 相關 issue 都屬於「回報的 duration／position 可能是 0 或視窗長度」，需要在 backend 層確認。

---

## 2. audio_service 0.18.19 與 audio_session 0.2.4（macOS：yes，部分功能缺）

- `pubspec.yaml:63-65`：macOS `pluginClass: AudioServicePlugin`、`sharedDarwinSource: true`。README 說明最低 macOS 10.12.2（`:420`，要求 Podfile `platform :osx, '10.12.2'`；我們是 12.0，已滿足）。
- README 平台表（`:20-31`）：macOS 的 background audio、headset clicks、play/pause/seek/rate/stop、fast forward/rewind、repeat/shuffle、queue manipulation、custom actions、notifications/control center、album art 都打勾；**「lock screen controls」macOS 空白、Android Auto/CarPlay 空白**。
- 原始碼（`darwin/audio_service/Sources/audio_service/AudioServicePlugin.m`）：
  - 使用 `MPRemoteCommandCenter`（`:89` 起，啟用 play/pause/stop/next/previous/skip/seek/changePlaybackPosition/togglePlayPause/repeat/shuffle/rate 等；`ratingCommand`、`likeCommand`、`bookmarkCommand` 明確 disable，`:130-135`）。第一次收到 `playing=true` 的狀態才 `activateCommandCenter`（`:180-188`）。
  - 使用 `MPNowPlayingInfoCenter`：title、album、artist、duration、artwork（macOS 10.13.2+）、播放速率、經過時間、`MPNowPlayingInfoPropertyIsLiveStream`（`isLive`），macOS 另外設 `center.playbackState`（`#if TARGET_OS_OSX`，`:292-295`）。
  - `setQueue`、`setPlaybackInfo`、`notifyChildrenChanged`、`androidForceEnableMediaButtons` 在 darwin 端都是直接回 `{}` 的空實作（`:192-195,221-224`）；自訂 action 由 Dart 端 handler 處理，不經原生端。
  - 封面：macOS 以 `extras["artCacheFile"]` 的**本機檔案路徑**建立 `NSImage`（`:206-225`）；`artCacheFile` 由 Dart 端 `AudioService` 用 `cacheManager`（`flutter_cache_manager`）先把 `artUri` 下載成檔案（`lib/audio_service.dart:960-1063,1251`）。`AudioService.init` 因此需要可用的 cache manager（App 本來就有 flutter_cache_manager）。
- audio_service 本身 `import audio_session`（`lib/audio_service.dart:8`、`:1723`），audio_session 的 macOS 實作存在（`macos/audio_session/.../AudioSessionPlugin.m`），但 darwin 端沒有 iOS 那種 `AVAudioSession`；`just_audio` 的 `handleAudioSessionActivation` 與 audio_session 在 macOS 的實質功能很有限（拔耳機的 becomingNoisy 在 macOS 由 audio_session 原生端提供與否**未驗證**；`core.dart:92` 有 "TODO: Check specifically if headphones were unplugged"）。
- 已知 issue：repo 內沒有找到 macOS 專屬 open issue；#1139（open）說 iOS ≥ 13 的 `playbackState` 沒回報——程式碼中 `center.playbackState` 只在 `TARGET_OS_OSX` 設，所以 macOS 不受影響、iOS 受影響。
- 目前 App 只有 `lib/platform/media_controls/media_controls_android.dart` 用 audio_service（Android 專用）。macOS 要自己加一個 macOS 版本的 `media_controls`。**Now Playing 與媒體鍵實際顯示／回應：未實測**。
- 不需要額外 entitlement／Info.plist key（沒有 `UIBackgroundModes` 之類的 macOS 對應；macOS 沒有背景模式需求）。

---

## 3. flutter_secure_storage 11.2.0 / flutter_secure_storage_darwin 0.4.3（macOS：yes，但預設設定在 ad-hoc 下**會失敗**）

### 3.1 套件行為（讀 darwin 0.4.3 原始碼與 README）
- `MacOsOptions` 預設 `usesDataProtectionKeychain = true`（`flutter_secure_storage-11.2.0/lib/options/macos_options.dart:24`）。darwin 端（`FlutterSecureStorage.swift:285-287`）只有該值為 true 時才加 `kSecUseDataProtectionKeychain = true`（0.3.2 起，CHANGELOG：「不再無條件加」）。
- `keychain-access-groups`：darwin README 的設定段（`README.md:16-32`）要求在 DebugProfile/Release entitlements 加 `<key>keychain-access-groups</key><array/>`，並說明 macOS 上它需要 provisioning profile（`:34-48`）；README 提供的替代方案是 `MacOsOptions(usesDataProtectionKeychain: false)`，走舊版（file-based login）Keychain，不需要 `keychain-access-groups` 或 provisioning profile。
- `groupId` 只在 iOS 加到 query（`FlutterSecureStorage.swift:290-293`，`#if os(iOS)`）。
- 0.4.2 起，data protection keychain 關閉時略過 synchronizable 查詢（CHANGELOG 0.4.2）。0.4.3：跨 accessibility level 找項目（#1269）。

### 3.2 實測：ad-hoc 簽章、App Sandbox、無 team ID（macOS 27）
測試程式直接用 `SecItemAdd`／`SecItemCopyMatching`（與套件的 query 同類：generic password、`kSecAttrAccessibleWhenUnlocked`），打包成 `.app`，`codesign -f -s - --entitlements <plist>`。

| 設定 | 結果 |
|---|---|
| Sandbox + ad-hoc，`kSecUseDataProtectionKeychain = true`（套件預設） | `SecItemAdd` → **-34018 "A required entitlement is not present"**；讀 → -25300 找不到 |
| 無 Sandbox + ad-hoc，DPK = true | 同樣 -34018 |
| Sandbox + ad-hoc，**DPK = false** | 新增 0、讀回正確；重建（換 cdhash）後的新 ad-hoc 二進位對舊項目只讀也成功，**沒有跳授權提示**（跑了兩次不同二進位） |
| Sandbox + ad-hoc，entitlements 加 `keychain-access-groups`（連空 `<array/>`） | 行程被 SIGKILL（exit 137），連 DPK=false 也一樣——AMFI 因「受限 entitlement 沒有 provisioning profile」直接殺掉 |
| 無 Sandbox + ad-hoc，DPK = false，**存取由 Sandbox 版本建立的同一個項目** | 阻塞，螢幕跳出「kc 想使用你鑰匙圈中的『fmp-kc-test』所儲存的機密資訊」授權視窗（ACL 屬於建立者） |

- 所以：**照 darwin README 的主設定（加 `keychain-access-groups`）在我們的條件下會讓 App 啟動即被殺**；**不加 entitlement 又用預設 DPK=true 則每次讀寫都 -34018**；**唯一在無 team ID 下可行的路是 `MacOsOptions(usesDataProtectionKeychain: false)`（實測可用）**。
- 實測沒有涵蓋：未沙箱／Developer ID 簽章與 ad-hoc 混用的升級情境。issue #1104（closed，2026-09-11，因修正 #1136 而關閉）的留言提到，更新器重寫整個 `.app` 後 Keychain ACL 綁 designated requirement，使用者每次更新會被詢問「想使用鑰匙圈中的…」，「永遠允許」只到下次重寫為止；該情境是未沙箱 + Developer ID，與我的沙箱 + ad-hoc 實測結果（沒有提示）不同，**不能互相推論**。
- DPK=false 之後項目放在使用者的 login keychain（`~/Library/Keychains/login.keychain-db`），`security find-generic-password -s <service>` 看得到項目；DPK true/false 是兩個不同的 keychain，之後改變設定會讀不到舊資料（macOS 目前沒有舊資料，所以越早定越好）。
- 相關 issue：#1104（closed）、#1176（closed，文件應警告 Keychain Sharing 需要 provisioning）、#804（closed，release 的 -34018）、#686（closed，signed+notarized 讀回 null）。

### 3.3 對我們
- 憑證存放在 macOS 可行，條件是明確傳 `mOptions: MacOsOptions(usesDataProtectionKeychain: false)`；目前 `FlutterSecureStorageAdapter.system`（`app/lib/platform/secure_storage/flutter_secure_storage_adapter.dart:31-40`）只傳 `aOptions`，沒有 macOS 選項。
- macOS 的 `Release.entitlements`／`DebugProfile.entitlements` 都**不要**加 `keychain-access-groups`。
- 持久化格式面：用 DPK=false 後 macOS 資料在 login keychain，換成 DPK=true（日後若有付費帳號）等於換儲存位置，需遷移。

---

## 4. flutter_inappwebview 6.2.0-beta.3 / flutter_inappwebview_macos 1.2.0-beta.3（macOS：真實作 partial，本 repo 現況為 stub）

- 現況：`app/pubspec.yaml` 直接依賴 `flutter_inappwebview_macos_stub`（`packages/flutter_inappwebview_macos_stub`，純 Dart）取代預設的 `flutter_inappwebview_macos`；理由寫在其 `pubspec.yaml`：真實作 1.2.0-beta.3 在目前 Xcode 編不過（`WebAuthenticationSession.swift:85` 的 `presentationAnchor(for:)` 需要 `@MainActor`），且「沒有修好的版本」。`.flutter-plugins-dependencies` 的 macOS 清單裡沒有 `flutter_inappwebview_macos`。**我沒有自己重現這個編譯失敗**，這裡引用專案內的說明。pub.dev 上 `flutter_inappwebview_macos` 最新版仍是 1.2.0-beta.3（2026-02-04），穩定版是 1.1.2（2024-10-02）。
- 真實作的原生碼（讀 pub cache）：
  - 最低 macOS 10.14（podspec `:25`、`Package.swift:9`），有 SPM 支援（1.2.0-beta.3 CHANGELOG「Add Swift Package Manager support」）。
  - `CookieManager` 全部走 `WKWebsiteDataStore.default().httpCookieStore`（`MyCookieManager.swift:16`，`@available(macOS 10.13, *)`），有 `setCookie`／`getCookies`／`getAllCookies`／`deleteCookie(s)`／`deleteAllCookies`；`userAgent` 設定映射到 `WKWebView.customUserAgent`（`InAppWebView.swift:145-146,701-702`）。
- **不需要自己的原生外掛也能驗證的部分（實測）**：我用純 `WKWebView` 在 Sandbox + ad-hoc 下測：
  - 只有 `app-sandbox`、**沒有** `network.client` → 頁面請求**完全沒有送出**（伺服器 0 個請求，導覽也沒有失敗回呼，只是卡住至 timeout）；
  - 加 `com.apple.security.network.client` → 頁面載入、`customUserAgent` 生效（頁內 `navigator.userAgent` 回自訂值）、`httpCookieStore.getAllCookies` 讀到 `HttpOnly` cookie（`SESSDATA=xyz httpOnly=true domain=127.0.0.1`）、逐一 `delete` 後再讀為 0。
  - 沒有測 cookie 跨重啟持久、沒有測真的登入 Bilibili／YouTube／NetEase（可能有額外限制）。
- entitlements：官方 example 的 entitlements 只有 `app-sandbox`、`cs.allow-jit`、`network.server`（沒有 `network.client`），所以不能當作設定參考；以上面實測為準，必須要 `network.client`。
- Info.plist：沒有看到必須的 key（要載 `http://` 非 loopback 同樣受 ATS 限制，未測 WKWebView 這一項）。
- 對我們：macOS 的登入 WebView 屬於 ADR 0012 §決定 8 要在 macOS 平台任務決定的項目；`PlatformCapabilities.loginWebView` 目前為假。WKWebView 本身與 cookie 能力在沙箱下可行（實測），但套件的 macOS 實作目前編不過。

---

## 5. window_manager 0.5.2（macOS：yes；套件已不維護）

### 5.1 功能（讀 `macos/window_manager/Sources/window_manager/WindowManager.swift`）
- `setTitleBarStyle`（`:379-402`）：`hidden` → `titleVisibility = .hidden`、`titlebarAppearsTransparent = true`、`styleMask.insert(.fullSizeContentView)`；`normal` 相反；**三顆紅綠燈按鈕由 `windowButtonVisibility`（預設 true，`lib/src/window_manager.dart:567`）控制 `isHidden`**。所以 `TitleBarStyle.hidden` 可以隱藏標題列又保留紅綠燈。（`mainWindow.isOpaque = false; hasShadow = true` 同時被設。）
- `startDragging`（`:513-519`）：`window.performDrag(with: window.currentEvent!)`（`currentEvent` 為 nil 時不做事）。`DragToMoveArea`（`lib/src/widgets/drag_to_move_area.dart`）= `GestureDetector(onPanStart: startDragging, onDoubleTap: maximize/unmaximize)`；本 App 的 `WindowDragArea`（`app/lib/ui/shell/window_title_bar.dart:20-39`）是同款自寫。
- 「最大化」在 macOS = `NSWindow.zoom`（`isMaximized` = `isZoomed`，`:152-166`），不是 macOS 全螢幕；`setFullScreen`／`isFullScreen`（`:196-212`）是另一組。`windowShouldZoom` 會送 `maximize` 事件並受 `setIsMaximizable` 控制（`:530-536`）；`WindowManagerChrome`（`app/lib/platform/window_chrome/window_manager_chrome.dart`）已用 `onWindowMaximize/Unmaximize` 追蹤。
- `setPreventClose`、`hide`/`show`/`focus`、`setSkipTaskbar`（切 `NSApplication` activation policy）、`setBadgeLabel` 在 macOS 都有實作。
- macOS 的雙擊標題列預設行為（系統偏好：縮放或最小化）在隱藏標題列後不再由系統處理，要自己接（`DragToMoveArea` 的 `onDoubleTap` 做 zoom）。
- 最低版本 macOS 10.15（`Package.swift:9`），podspec 寫 10.11。

### 5.2 已知問題（leanflutter/window_manager，倉庫在 2026-09-21 批次關閉 issue）
- README 開頭宣告：此外掛遷移到 `libnativeapi/nativeapi-flutter`；維護者在 issue 留言：「window_manager 0.5.x 不再維護；0.6.0 起以 nativeapi 重建，平台碼移走」。0.5.2 是最後一版（2026-07-04）。
- **#565（closed `NOT_PLANNED`）**：macOS Tahoe (26.0) 上 `TitleBarStyle.hidden` 時，放在視窗最上緣的按鈕點不到（隱形標題列蓋住內容）。留言的 workaround：同時呼叫 `setAsFrameless()` + `TitleBarStyle.hidden`，點擊可穿透但 hover 游標不正常。我們要在 macOS 27 實測才知道是否影響。
- **#501（closed `NOT_PLANNED`）**：macOS 14+ `hide()` 兩次後無法從 Dock 再開啟視窗（和「關視窗保留在 tray／Dock」的設計有關）。
- **#333（closed）**：最大化／還原後第一次點擊沒反應；原因與加了 NSToolbar 有關，非 TitleBarStyle.hidden 本身。
- #379（`hide()` 在全螢幕下黑畫面）、#431（`hide()` macOS 行為）、#541（`setSize` 卡住）等多半是批次關閉，不代表已修。

### 5.3 `macos_window_utils`（比較用）1.9.1（2026-01-05，macosui.dev 維護）
- README 功能：隱藏／顯示標題、啟用 full-size content view、顯示／隱藏／啟用紅綠燈、**取得與設定紅綠燈位置**、加入 NSToolbar 並設樣式（含讓 toolbar 區域穿透滑鼠事件的 widget）、視窗透明／材質（`NSVisualEffectView`）、陰影、最小／最大尺寸、`NSWindowDelegate` 事件、全螢幕與 zoom、最低 macOS 10.14.6。
- 與 window_manager 的差別：偏 macOS 視窗外觀（材質、toolbar、紅綠燈位置），沒有跨平台抽象；沒有 `startDragging`/`DragToMoveArea` 的對應。與 window_manager 同時使用在 macOS 上需要自己處理哪一個擁有 NSWindow 設定。**我沒有用它做任何實測。**

---

## 6. file_picker 13.1.0、share_plus 13.3.1、url_launcher 6.3.3、connectivity_plus 7.3.1、path_provider 2.1.6、package_info_plus 10.2.2

| 套件 | macOS 實作 | 需要的 entitlement／Info.plist | 備註 |
|---|---|---|---|
| file_picker（`file_picker_darwin` 2.1.3） | `NSOpenPanel`／`NSSavePanel`（`MacOSFilePickerHandler.swift:96,161,214,263`），以 `beginSheetModal` 呈現 | **沙箱必要**：`com.apple.security.files.user-selected.read-only`（只選檔讀取）或 `...read-write`（`saveFile()` 必須）。README：「沒有它每次 pick／save 都以 entitlement 錯誤失敗」。兩個 entitlements 檔都要加 | `initialDirectory` 在沙箱內只對「已授權過的目錄」生效，否則被 Powerbox 靜默忽略（`README.md:31-35`）。App 用於安裝插件 `.js`、還原備份等（`lib/platform/files/file_picker_dialogs.dart`） |
| share_plus（13.3.1） | `NSSharingServicePicker`（`SharePlusMacosPlugin.swift:56-59`），需要 `registrar.view` | 不需要額外 entitlement（分享的檔案要在 App 可讀的範圍，例如容器內） | 需有視窗才能顯示 picker |
| url_launcher（`url_launcher_macos` 3.2.6） | `NSWorkspace.shared.open(url)`（`UrlLauncherPlugin.swift:54`） | 沙箱下開 `http(s)` 預設瀏覽器不需要 entitlement | — |
| connectivity_plus（7.3.1） | `NWPathMonitor`（`PathMonitorConnectivityProvider.swift`） | 無 | README `:132`：NWPathMonitor 觀測值可能多筆或不可靠（連線恢復時先 none 後 wifi） |
| path_provider（`path_provider_foundation` 2.6.0） | Dart + FFI 呼叫 `NSSearchPathForDirectoriesInDomains`（2.6.0 起不再是 plugin；2.5.0 曾因 production 建置問題撤回，CHANGELOG） | 無 | 見下方路徑 |
| package_info_plus（10.2.2） | 讀 Info.plist | 無 | macOS 的 `installerStore` 為 null（README `:89`）；版本來自 `FLUTTER_BUILD_NAME`／`FLUTTER_BUILD_NUMBER` |

### 6.1 沙箱下 path_provider 的真實路徑（實測 + 讀 `path_provider_foundation_real.dart:112-140`）
Sandbox + ad-hoc、bundle id `com.personal.fmp.rltest` 時，`FileManager.urls(for:in:.userDomainMask)` 回傳：

| API | `NSSearchPathDirectory` | 容器路徑 |
|---|---|---|
| `getApplicationSupportDirectory()` | `.applicationSupportDirectory` | `~/Library/Containers/<bundle id>/Data/Library/Application Support/<bundle id>` |
| `getApplicationCacheDirectory()` | `.cachesDirectory` | `~/Library/Containers/<bundle id>/Data/Library/Caches/<bundle id>` |
| `getTemporaryDirectory()` | **同樣是 `.cachesDirectory`**（`getTemporaryPath` 回傳 Caches，`:41-43`）→ 即與 Cache 相同的 `…/Library/Caches/<bundle id>`；注意 `NSTemporaryDirectory()` 本身是 `…/Data/tmp/`，與 path_provider 回傳的不同 |
| `getApplicationDocumentsDirectory()` | `.documentDirectory` | `~/Library/Containers/<bundle id>/Data/Documents`（**不加** bundle id 子目錄） |
| `getLibraryDirectory()` | `.libraryDirectory` | `~/Library/Containers/<bundle id>/Data/Library` |
| `getDownloadsDirectory()` | `.downloadsDirectory` | `~/Library/Containers/<bundle id>/Data/Downloads`（沙箱容器內，不是使用者真正的 `~/Downloads`；要寫真正的 Downloads 需要 `files.downloads.read-write`，本次未測） |

- macOS 只有 Application Support 與 Caches 會被加上 `<bundle id>` 子目錄（`:129-139`，註解：非沙箱時這些是共享目錄；沙箱時也一樣加）。`NSHomeDirectory()` 在沙箱內就是 `…/Containers/<bundle id>/Data`。
- 本 repo 已存在 `~/Library/Containers/com.personal.fmp.dev/`（先前跑過 dev flavor 的容器）；dev 與 prod bundle id 不同（`com.personal.fmp.dev` vs `com.personal.fmp`），所以兩個 flavor 的容器天然分開。
- 用到的地方：`app/lib/platform/platform.dart:143,161,163,191,193,248,250,382`。

---

## 7. isar_community_flutter_libs 3.3.2（macOS：yes）
- 套件內有 `macos/libisar.dylib`（2,187,120 bytes），`file`／`otool` 結果：**Mach-O universal（x86_64 + arm64）**；arm64 切片 `LC_BUILD_VERSION minos 11.0`；install name `@rpath/libisar.dylib`；已有 linker-signed ad-hoc 簽章（`flags=0x20002(adhoc,linker-signed)`）。
- 以 CocoaPods 提供：`isar_community_flutter_libs.podspec` 用 `s.vendored_libraries = 'libisar.dylib'`、`s.platform = :osx, '10.11'`、`s.dependency 'FlutterMacOS'`；沒有 `Package.swift`，所以 Flutter 會為專案產生 Podfile。`Classes/IsarFlutterLibsPlugin.swift` 只是一個回傳平台版本的空殼。
- `app/macos/Podfile.lock`（未提交的生成檔）已列 `isar_community_flutter_libs (1.0.0)`。
- 舊版 App 從沒發過 macOS 版（`app/AGENTS.md:115`：「iOS、macOS 的舊版沒有發過」），所以 macOS 沒有「舊 Isar 資料匯入」的實際來源。

---

## 8. media_kit 1.2.6（macOS：本 App 不用；對建置無影響）
- `media_kit` 的 `pubspec.yaml` 沒有 `flutter: plugin:` 區塊，是純 Dart（FFI）；macOS 時在執行期以 `DynamicLibrary.open('Mpv.framework/Mpv')` 找 libmpv（`lib/src/player/native/core/native_library.dart:60-62`），找不到才丟例外。
- `media_kit_libs_windows_audio` 1.0.9 只宣告 `windows` 平台。`app/.flutter-plugins-dependencies` 的 macOS 外掛清單（16 項）**沒有任何 `media_kit*`**；`Podfile.lock` 也沒有。所以 macOS 建置**不會**連結任何 libmpv，二進位大小不受影響。
- Dart 端 `lib/playback/backends/media_kit_backend.dart` 仍會被編進 macOS 的 AOT（`audio_backends.dart` 同一個 switch 含兩個後端），只有純 Dart 程式碼，不載入 libmpv，除非 `AudioBackendKind.mediaKit` 被選到。
- 沒有 `just_audio_media_kit`（pubspec 沒有）；ADR 0018 的選擇（Apple 用 just_audio）與目前依賴一致。

---

## 9. macOS 的單一實例
實測（本機，`LSUIElement` 小程式，Sandbox + ad-hoc，每次 `sleep` 25 秒保持執行）：

| 操作 | 一般 bundle | 加 `LSMultipleInstancesProhibited=true` |
|---|---|---|
| 連續兩次 `open X.app` | 1 個行程（LaunchServices 重用已執行的實例） | 1 個 |
| 再 `open -n X.app` | 2 個 | **仍 1 個**（被擋下） |
| 直接執行 `X.app/Contents/MacOS/<exe>` | 3 個 | **2 個**（直接 exec 不受 LS 管轄，擋不住） |

- Apple 文件 `LSMultipleInstancesProhibited`：「Boolean，是否允許多個**使用者**同時啟動」（https://developer.apple.com/documentation/bundleresources/information-property-list/lsmultipleinstancesprohibited ）；對同一使用者的 `open -n` 實測有擋。
- 雙擊 Finder／`open` 預設就重用（`NSWorkspace.OpenConfiguration.createsNewApplicationInstance` 預設 false：「預設開啟已在執行的 App」，https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration/createsnewapplicationinstance ）。
- 直接從終端機跑二進位（`flutter run`、`open -n`、diagnostics 腳本）會產生多個實例；若要擋，需 App 自己加鎖（例如 `flock` 檔案或 `NSRunningApplication.runningApplications(withBundleIdentifier:)`），沙箱內鎖檔放在容器內。
- 「重新開啟／帶到前景」：重用已執行的實例時，AppKit 會呼叫 `applicationShouldHandleReopen(_:hasVisibleWindows:)`（https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationshouldhandlereopen(_:hasvisiblewindows:) ）。Flutter 3.47 的 `FlutterAppDelegate.mm`（engine 於 flutter 6a19cca564，共 200 行）**沒有實作它**（只實作 `applicationWillFinishLaunching`、`application:openURLs:`、`applicationShouldTerminate:` 等），`FlutterAppDelegate.h` 也沒宣告；範本 `AppDelegate.swift`（`app/macos/Runner/AppDelegate.swift`）只覆寫了 `applicationShouldTerminateAfterLastWindowClosed`（回 true）與 `applicationSupportsSecureRestorableState`。要在視窗被隱藏後點 Dock 圖示復原，需要 App 自己覆寫 `applicationShouldHandleReopen`。`window_manager` 0.5.2 的 macOS 原始碼沒有處理 reopen。
- 目前 `applicationShouldTerminateAfterLastWindowClosed = true`：關掉最後一個視窗就結束 App；若 macOS 版也要「關閉視窗後留在 tray」則要改這個回傳值。

---

## 10. macOS 上 App 自行重啟（資料重設／還原後）
實測（Sandbox + ad-hoc，`rl` 小程式；子行程 log 寫到容器的 `tmp/rl.log`）：

| 方式 | 結果 |
|---|---|
| `NSWorkspace.shared.openApplication(at: bundleURL, configuration: createsNewApplicationInstance=true)` | 成功啟動新實例（新 pid；completion 的 `app` 為 nil/-1，無 error），原行程接著 `exit` |
| 沙箱內 `Process` 執行 `/usr/bin/open -n <bundle>` | 成功（`open` exit 0），新實例啟動 |
| 沙箱內 `Process` 啟動分離的 `/bin/sh -c 'while kill -0 <pid>; do sleep 0.2; done; /usr/bin/open -n <bundle>'` | 成功：原行程結束後新實例啟動（這是 ADR 0022 macOS 更新腳本的同一種形式） |
| 上述三者想傳 `--args child`（或 `OpenConfiguration.arguments`） | **參數被丟掉**：新實例的 `argv` 只有執行檔路徑；同一個命令從非沙箱的 shell 執行（`open -n X.app --args child`）則參數正常到達 |
| 沙箱內由 App 啟動的 `sh` 子行程寫入 `~/Desktop` 或 `/Applications` | **被沙箱擋下**：`touch: Operation not permitted`（`/Applications` 為 `root:admin drwxrwxr-x`；子行程繼承沙箱） |

- 結論：沙箱 App 可用 `NSWorkspace.openApplication` 或 `open -n` 重啟自己，只是不能靠命令列參數傳狀態（要把「重啟後要做什麼」寫進容器內的檔案或偏好設定）。
- 同時意味著：ADR 0022 寫的「由小腳本等 App 結束後把舊 `.app` 改名 `.old`、放上新的」在**沙箱內的 App 啟動**的腳本無法改動 `/Applications`（我只測了 `touch`；對 `mv`／覆寫 `.app` 沒測，但同樣受沙箱檔案限制）。這屬於更新流程的前提，需要另行決定；本調查只記錄事實。
- Apple 文件：https://developer.apple.com/documentation/appkit/nsworkspace/openapplication(at:configuration:completionhandler:) 。
- `Process` 啟動 `/usr/bin/open` 在這台機器 macOS 27 沙箱下可用，未見額外 entitlement 要求。

---

## 11. CocoaPods 與 SPM（Flutter 3.47.5，macOS）
- `app/.flutter-plugins-dependencies`：`"swift_package_manager_enabled":{"ios":true,"macos":true}`；`app/macos/Flutter/ephemeral/Packages` 存在（`FlutterGeneratedPluginSwiftPackage`）。Flutter 工具支援 SPM 與 CocoaPods 同時存在（混合）。
- macOS 的 16 個外掛中**沒有 `Package.swift` 的**（讀 pub cache）：
  - `flutter_js` 0.8.7：只有 `macos/flutter_js.podspec`；
  - `isar_community_flutter_libs` 3.3.2：只有 `macos/isar_community_flutter_libs.podspec`；
  - `path_provider_foundation` 與 `flutter_inappwebview_macos_stub` 沒有原生碼（`native_build:false`）。
  - 其餘 `audio_service`、`audio_session`、`connectivity_plus`、`file_picker_darwin`、`flutter_secure_storage_darwin`、`just_audio`、`package_info_plus`、`screen_retriever_macos`、`share_plus`、`sqflite_darwin`、`url_launcher_macos`、`window_manager` 都有 `Package.swift`。
- 因為仍有 2 個 CocoaPods 外掛，Flutter 會產生 Podfile。工作樹中未提交的 `app/macos/Podfile`（內容）：
  - `platform :osx, '12.0'`；`project 'Runner', { 'Debug' => :debug, 'Profile' => :release, 'Release' => :release }`；
  - `target 'Runner'` 內 `use_frameworks!` + `flutter_install_all_macos_pods`，`RunnerTests` 以 `inherit! :search_paths`；
  - `post_install` 對每個 pod target 呼叫 `flutter_additional_macos_build_settings`。
  - **只對應三個無 flavor 的 configuration**；專案 `Runner.xcodeproj` 有六個 flavor configuration（`Debug-dev`、`Profile-dev`、`Release-dev`、`Debug-prod`…，`project.pbxproj:1006-1331`）。`app/AGENTS.md:137-139` 已記載這個後果：其他 configuration CocoaPods 一律當 release，`Debug-dev` 的 pod 也用 release 編；要在 Xcode 除錯 pod 時才需要補齊六個 configuration 的對應。
- `app/macos/Podfile.lock`（未提交）：只列 `flutter_js (0.0.1)`、`FlutterMacOS (1.0.0)`、`isar_community_flutter_libs (1.0.0)` 三個 pod，`COCOAPODS: 1.17.0`；`Flutter-Debug.xcconfig`、`Flutter-Release.xcconfig` 被加上 `#include? "Pods/Target Support Files/Pods-Runner/Pods-Runner.{debug,release}.xcconfig"`；`pbxproj` 增加 `Pods_Runner.framework` 等引用（皆為工作樹未提交的生成變更）。
- 其他會參與 macOS 建置的原生資產：`objective_c` 9.5.0（path_provider_foundation 用 FFI）與 `sqlite3` 3.6.0（build hooks，`hooks` 2.2.0／`native_toolchain_c` 0.19.3）以 native assets 在建置時編譯，不走 CocoaPods／SPM。
- **flutter_js 在 macOS 沒有 QuickJS 原生庫**（與第 0 節相關，單獨列出）：
  - `flutter_js-0.8.7/macos/Classes/` 只有 `FlutterJsPlugin.swift`（回傳平台版本的空殼）；
  - 整個套件裡含 QuickJS 原生庫的只有 `windows/shared/quickjs_c_bridge.dll` 與 `linux/shared/libquickjs_c_bridge_plugin.so`（Android 另靠 maven 依賴 `fastdev_quickjs_runtime`）；
  - `lib/quickjs/ffi.dart:119-131`：macOS 時 `_qjsLib = DynamicLibrary.process()`（只在 `FLUTTER_TEST` 時如此；其他情形走 `DynamicLibrary.process()` 的最後一個分支）→ 在 macOS 的 app 行程內找不到 QuickJS 符號（例如 `jsThrow`）；
  - README：「macOS 使用系統的 JavaScriptCore；Windows、Linux 用 QuickJS」，也就是這個套件在 Apple 平台預期走 `JavascriptCoreRuntime`（`lib/javascriptcore/`），不是 `QuickJsRuntime2`；
  - 本 App 的插件執行環境是 `QuickJsRuntime2` 的子類（`app/lib/plugins/runtime/plugin_worker.dart:174-190`，`app/pubspec.yaml` 的 flutter_js 註解亦寫明依賴 QuickJS 行為）。`app/AGENTS.md:33` 也提到「插件執行環境的 QuickJS … 在 macOS 主機載不到」（針對測試）。
  - 這點不在你列的 11 項裡，但會影響 macOS 上「插件」能否執行，所以一併記錄。**我沒有實際在 macOS app 內跑 `QuickJsRuntime2` 確認會失敗**，結論來自原始碼：macOS 目錄沒有 QuickJS 的 C 原始碼或預編譯庫。

---

## 12. 目前 repo 內 macOS 設定現況（對照用）
- `app/macos/Runner/DebugProfile.entitlements`：`app-sandbox`、`cs.allow-jit`、`network.server`。
- `app/macos/Runner/Release.entitlements`：只有 `app-sandbox`。
- **兩份都沒有 `com.apple.security.network.client`**。Flutter 官方文件（https://docs.flutter.dev/platform-integration/macos/building ）：「沒有 `network.client`，網路請求會失敗：`SocketException: Connection failed (OS Error: Operation not permitted, errno = 1)`」；本機實測 AVPlayer、WKWebView 在沒有它時都不會送出任何請求。
- 兩份都沒有 `files.user-selected.*`；`Info.plist` 沒有 `NSAppTransportSecurity`。
- `CODE_SIGN_IDENTITY = "-"`（ad-hoc）；App target `CODE_SIGN_STYLE` 為 Automatic（Debug）/Manual（Release）；`PRODUCT_BUNDLE_IDENTIFIER = com.personal.fmp`（prod），dev 為 `com.personal.fmp.dev`。
- `AppDelegate.swift`：`applicationShouldTerminateAfterLastWindowClosed → true`；沒有 reopen 處理。
- `ADR 0018`（`:35,:55`）與 `ADR 0022`（`:16,:34,:56,:91`）已決定 macOS 用 just_audio + audio_service、發未公證 zip、更新用小腳本。

---

## 對 FMP 的影響與風險排序

1. **（阻擋）兩份 entitlements 都沒有 `com.apple.security.network.client`**：沙箱內所有出站連線（Dart `dio`、AVPlayer、WKWebView）都會被擋；實測 AVPlayer 與 WKWebView 是「靜默失敗」（伺服器 0 請求）。必加到 `DebugProfile.entitlements` 與 `Release.entitlements`。若要選檔還需要 `files.user-selected.read-write`（`saveFile` 必須）。
2. **（阻擋插件）flutter_js 0.8.7 在 macOS 沒有 QuickJS 原生庫**：App 的插件執行環境依賴 `QuickJsRuntime2`，macOS 目錄只有空殼外掛；套件預期 Apple 平台走 JavaScriptCore。插件（Bilibili／YouTube／NetEase 的取流邏輯）在 macOS 能不能跑，取決於這點。（原始碼推論，未在 macOS app 內實跑。）
3. **（高）憑證存放**：flutter_secure_storage 預設 `usesDataProtectionKeychain: true` 在 ad-hoc／無 team ID 下 `-34018`（實測）；按 README 加 `keychain-access-groups` 會讓 ad-hoc 簽章的 App 被 AMFI 直接 SIGKILL（實測，連空 `<array/>` 也會）。**只有 `MacOsOptions(usesDataProtectionKeychain: false)` 在沙箱 + ad-hoc 下實測可用**（也不會因重建二進位而跳授權視窗）。目前的 adapter 沒有傳 macOS 選項。DPK 的選擇會決定資料存哪個 keychain，之後更換要遷移。更新器重寫 `.app` 造成的授權提示在非沙箱情境有回報（#1104 留言），沙箱情境我沒重現。
4. **（高）Bilibili DASH 音訊／直播在 AVPlayer 的實況**：合成樣本（單檔 fMP4 + sidx + Range、HLS fMP4、HLS TS，含 Referer／UA／Cookie）全部可播且標頭完整到達；但依賴未公開的 `AVURLAssetHTTPHeaderFieldsKey`，且**對 CDN 回的 `Content-Type` 敏感**（`application/octet-stream` + `.m4s` 失敗）。真實 Bilibili CDN 回應、E-AC-3／FLAC 軌、真實 live HLS 都沒測。FLV 未測。
5. **（中）http:// 音訊 URL 受 ATS 阻擋**：AVPlayer 實測 `http://example.com` → `-1022`；loopback 豁免。`Info.plist` 目前沒有 ATS 設定。是否有來源回傳 http URL 沒查。
6. **（中）window_manager 0.5.2 已停止維護**：macOS 26 上 `TitleBarStyle.hidden` 時頂端按鈕點不到的回報（#565，`NOT_PLANNED`）要在 macOS 27 實測；功能面 `TitleBarStyle.hidden` + 紅綠燈保留、`startDragging`、zoom、全螢幕在原始碼都有實作。自繪標題列需預留紅綠燈區域。
7. **（中）just_audio 在 Apple silicon 的 duration／position 問題**：#1599（MP3 duration=0、position 卡 0，open）、#1435（open）；live HLS 的 `duration` 會是 seekable 視窗長度而非 null（程式碼推論 + AVPlayer 實測 seekable range）。
8. **（中）重啟與更新**：沙箱 App 可用 `NSWorkspace.openApplication`／`open -n`／分離的 sh 重啟自己，但命令列參數會被丟掉；沙箱子行程無法寫 `/Applications` 與 `~/Desktop`，ADR 0022 的 macOS 更新腳本前提需要另外確認。
9. **（中）macOS 登入 WebView**：真實 `flutter_inappwebview_macos` 1.2.0-beta.3 編不過（專案內說明，未獨立重現），目前以 stub 取代；底層 WKWebView 在沙箱 + `network.client` 下 UA、cookie（含 HttpOnly 讀取與刪除）實測可行。
10. **（低）單一實例與 reopen**：Finder／`open` 預設重用；`open -n` 與直接 exec 會多開，`LSMultipleInstancesProhibited` 擋得住 `open -n` 但擋不住直接 exec；Flutter 3.47 的 AppDelegate 沒有 `applicationShouldHandleReopen`，要隱藏視窗後復原需自行覆寫。
11. **（低）Podfile 與 flavor**：仍有 `flutter_js`、`isar_community_flutter_libs` 兩個 CocoaPods 外掛，所以 Flutter 會生成 Podfile（未提交），目前只映射 Debug／Profile／Release，flavor 的 pod 以 release 編（`app/AGENTS.md` 已記）；libisar 為 universal dylib（x86_64 + arm64，arm64 `minos 11.0`），部署目標 12.0 無衝突；macOS 不會拉進 media_kit／libmpv。
12. **（低）macOS 部署版本**：所有套件最低都 ≤ 10.15，專案 12.0，沒有衝突。

## Caveats / Not Found
- 沒有真實 Bilibili 音訊 URL 可測（API 回 412），「Bilibili DASH 在 AVPlayer 可播」只由本機合成 fMP4 驗證。
- FLV、E-AC-3、FLAC、真實 live HLS、NetEase／YouTube 的流、gapless 實際交接、audio_service 的 Now Playing／媒體鍵實際顯示、`audio_session` 在 macOS 的拔耳機事件、Cookie 跨重啟持久、`files.downloads.read-write`、macOS 27 上 window_manager 的 #565，皆**未實測**。
- 我的 keychain 實測在這台機器（macOS 27.0.1、Xcode 27.1）上完成，其他 macOS 版本行為可能不同。
- 測試殘留：`~/Library/Containers/com.personal.fmp.{kctest,rltest,avtest,wktest}` 四個空的沙箱容器（我的測試程式建立；`rm` 被系統保護擋下，需透過 Finder 或重新啟動後再刪）；測試用 keychain 項目 `fmp-kc-test` 已刪除。另外執行 `screencapture` 時，系統可能跳出「Orca 要錄製螢幕」的隱私權詢問視窗，以及一個尚未關閉的鑰匙圈授權視窗（我的 `nosb dpk=0` 測試造成），若看到請手動按「拒絕」。
