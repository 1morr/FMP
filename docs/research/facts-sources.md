# 事實：音源

查證過的外部事實，一條一個編號，編號不重用。可信度標記與 `legacy:`、`archive:` 的意思見 [brief〈事實索引〉](../design-brief.md)。

## 事實

### Bilibili

- **F1** 匿名請求 `/x/web-interface/view` 回 HTTP 412；`/x/web-interface/wbi/view` 與 `/x/player/pagelist` 回 200（2026-09-15）。出處：`legacy:lib/data/sources/bilibili_source.dart:77-83`。可信度：舊版程式碼。
- **F2** 風控碼 `-352`、`-412`、`-509`、`-799` 與 HTTP 412、429 要當限流退避，換 buvid 指紋救不回來。節流針對匿名身分：2026-09-22 同時間窗匿名 23/40 被擋、帶登入 0/40；`curl`、`okhttp` 這類 UA 必被擋。出處：`legacy:lib/data/sources/bilibili_source.dart:923-940`、`legacy:lib/data/sources/bilibili_exception.dart:15-24`。可信度：舊版程式碼。
- **F3** 認證失敗是 HTTP 200 加 JSON `code: -101/-111`，不是 401；cookie 刷新用 RSA-OAEP，刷新後仍 `-101` 才是憑證真的失效；QR 輪詢回 `86038` 表示過期。出處：`legacy:lib/services/account/bilibili_auth_interceptor.dart:10-14,78`。可信度：舊版程式碼。
- **F4** 媒體與圖片 CDN 要 Referer（不帶結尾斜線）加瀏覽器的 User-Agent（事實 F22，舊版的媒體請求也一律帶瀏覽器 UA）；API 要 Referer（帶斜線）加 Origin；媒體請求不帶憑證。出處：`legacy:lib/data/sources/source_http_policy.dart:8-10,45,73-84,100-104`；M0 票 11 的實測（事實 F22）。可信度：舊版程式碼，媒體 header 的部分 2026-11-12 實測。
- **F5** 串流網址的有效期寫在 `deadline` 參數（unix 秒），實測約 7178 秒；要讀參數，不要寫死。出處：`legacy:lib/data/sources/bilibili_source.dart:429-445`。可信度：舊版程式碼。
- **F6** `/x/player/playurl` 的 `fnval=16` 回 DASH 音訊軌（m4a/AAC），`fnval=0` 回 FLV；點播沒有 HLS。Apple 平台的 AVPlayer 不播 FLV。出處：`legacy:lib/data/sources/bilibili_source.dart:297-426`。可信度：舊版程式碼。
- **F7** 直播：mpv 開流後約 50 秒內位置與時長都是 0；Apple 平台要改用 h5 的 HLS（aac）。出處：`legacy:lib/services/audio/media_kit_audio_service.dart:555-565`（Windows，舊版程式碼）；`archive:docs/adr/0036` §決定 7（Apple，上一版文件【待重驗】）。
- **F20** 匿名影片搜尋：`GET https://api.bilibili.com/x/web-interface/search/type?search_type=video&page=1&keyword=<關鍵字>`，帶瀏覽器 UA、`Referer: https://search.bilibili.com/`、`Origin: https://search.bilibili.com`，以及本地亂數產生的指紋 cookie（`buvid3=<8-4-4-4-12 大寫十六進位>infoc; buvid4=…; b_nut=<unix 秒>; _uuid=<同 buvid3>; buvid_fp=<同 buvid3>`），回 HTTP 200、JSON `code: 0`。結果在 `data.result`，每筆有 `bvid`、`title`（關鍵字以 `<em class="keyword">` 標出，含 `&amp;` 這類 HTML 實體）、`author`、`duration`（`m:ss` 或 `h:mm:ss` 字串）；舊版把沒有 `data.result` 當成零筆。不用 WBI 簽名。出處：`legacy:lib/data/sources/bilibili_source.dart:86,90-108,476-516`、`legacy:lib/data/sources/source_http_policy.dart:21-27,138-152`；M0 票 08 的 bilibili 插件（`app/plugins/bilibili/src/index.ts`）在 macOS、iOS 模擬器、Android 模擬器、Windows 各匿名搜尋一次都拿到結果。可信度：舊版程式碼，2026-11-12 四平台實跑。
- **F21** 匿名解析串流（點播）：先 `GET https://api.bilibili.com/x/player/pagelist?bvid=<bvid>` 取分 P 清單（`data` 是陣列，每筆有 `cid` 與從 1 起算的 `page`），再 `GET https://api.bilibili.com/x/player/playurl?bvid=<bvid>&cid=<cid>&fnval=16`（事實 F6）。兩支都不用 WBI 簽名，帶瀏覽器 UA、`Referer: https://www.bilibili.com/`、`Origin: https://www.bilibili.com`（事實 F4）與事實 F20 的指紋 cookie，回 HTTP 200、JSON `code: 0`。音訊軌在 `data.dash.audio`，每筆有 `baseUrl`（與 `base_url` 相同）、`bandwidth`（bit/s）、`codecs`；2026-11-12 匿名拿到兩條 `mp4a.40.2`（`bandwidth` 68646 與 134695），網址在 `upos-hz-mirrorakam.akamaized.net`、副檔名 `.m4s`，query 帶 `deadline` 與簽名參數 `upsig`。`BV1xx411c7mD`（av170001）的 pagelist 現在只有一個分 P。錯誤代碼舊版的分類：`-404`、`-503`、`62002` 是不可用，`-403`、`62012` 是沒有權限，`-10403` 是地區限制。出處：`legacy:lib/data/sources/bilibili_source.dart:327-376,649-672`、`legacy:lib/data/sources/bilibili_exception.dart:43-50`；M0 票 10 的錄製（`app/plugins/bilibili/fixtures/resolveStream/first-part.json`）。可信度：端點與回應 2026-11-12 匿名實測；錯誤代碼是舊版程式碼，沒有實測。
- **F22** 部分串流網址會對播放器自己的 User-Agent 回 HTTP 403：2026-11-12 匿名解析 `BV14gQeBNEix`，最高頻寬音訊軌的主網址（`upos-hz-mirrorakam.akamaized.net`）與 `backupUrl`（`upos-sz-mirrorcosov.bilivideo.com`）帶 Referer 時，User-Agent 是 ExoPlayer 的（`…ExoPlayerLib/1.4.1`）或 AVPlayer 的（`AppleCoreMedia/…`）都回 403，瀏覽器的回 206；`bilivideo.com` 那台不帶 Referer 也是 403，akamai 那台不帶 Referer 仍回 206。其他影片（`BV1xx411c7mD`、`BV1DXYCzrENa`）的 akamai 網址對 AppleCoreMedia 與不帶 Referer 都回 206，所以會不會擋看網址，播放時是偶發的：同一天 iOS 模擬器與 Android 模擬器各有一次第一首播放失敗（AVPlayer `-1102`、ExoPlayer `Response code: 403`），macOS 與重試時正常。B 站 CDN 回 `Content-Type: video/mp4`、`Accept-Ranges: bytes`，Range 請求回 206（事實 M11）。出處：`scripts/experiments/bilibili-cdn-headers/`（`probe.sh`、`hosts.sh`）；M0 票 11 的 Comments。可信度：2026-11-12 匿名實測。

### YouTube

- **F8**【待重驗】2026-08-26 起，ANDROID_VR client 不帶 PO token 的 googlevideo 網址只給約前 60 秒，之後 Range 一律 403；2026-09-30 實測 VISIONOS、IOS client 給完整長度的明文網址，不需要 PO token。client 每隔幾個月會變，解析串流要準備候選 client 序列。出處：archive 的 `youtubejs-probe.md`〈哪個 client 能用〉。可信度：上一版文件。
- **F9** 帶登入的 InnerTube `/player` 要用 WEB client，並帶 Origin 與 Referer 才通過 SAPISIDHASH 驗證；必要的 cookie 是 `SAPISID`、`__Secure-1PSID`、`__Secure-3PSID`。出處：`legacy:lib/data/sources/youtube_source.dart:60-70,407-410`。可信度：舊版程式碼。
- **F10** 每種串流類型先匿名試，失敗再帶登入重試同一類型；先把所有類型都匿名試完，會拿到含影像、位元率 3–5 倍的串流。出處：`legacy:lib/data/sources/youtube_source.dart:338-352`。可信度：舊版程式碼。
- **F11** googlevideo 網址約 1 小時過期；libmpv 分段請求之間連線閒置會被 CDN 切斷（WSAECONNRESET）。出處：`legacy:lib/data/sources/youtube_source.dart:52-54`、`legacy:lib/services/audio/media_kit_audio_service.dart:195-232`。可信度：舊版程式碼。
- **F12**【待重驗】Google 擋嵌入式 WebView 登入：Android 要從 UA 拿掉 `; wv`，iOS 的 WKWebView 要補成 Safari 形狀的 UA；Windows WebView2 的預設 UA 可以登入。登入完成看 cookie，不看網址；登出要清掉 WebView 的全部 cookie（Google 會寫地區網域與 CHIPS 分區 cookie）。出處：archive 的 `r1-youtube-login.md`、`archive:docs/adr/0029` §決定 9、11、`archive:docs/adr/0037` §決定 11。可信度：上一版文件。
- **F13**【待重驗】Windows 的 WebView 登入偶爾卡在 `accounts.youtube.com/accounts/SetSID` 或程序消失，原因不明，重開 App 再登入就好。出處：archive 的 `r1-youtube-login.md`〈Windows 跳轉時的偶發失敗〉。可信度：上一版文件。

### 網易雲音樂

- **F14** 播放串流走 eapi `/eapi/song/enhance/player/url/v1`，有效期看回應的 `expi`，實測約 1200 秒。出處：`legacy:lib/data/sources/netease_source.dart:40,69-70`。可信度：舊版程式碼。
- **F15** VIP 看 `fee`（1 或 4）；`flag & 4` 不是 VIP 標記（歌曲 139774 是 `flag=6`，匿名就拿到 320 kbps）。`cloudsearch` 的 `privilege.fee` 對 VIP 歌可能回 0，以 `song.fee` 為準。出處：`legacy:lib/data/sources/netease_source.dart:697-698,849-940`。可信度：舊版程式碼。
- **F16** 未登入時的失敗長相是 `code=404` 或 `301`、`fee=0`、`url=null`，要提示登入而不是引導付費（#87）。出處：`legacy:lib/data/sources/netease_source.dart:849-940`。可信度：舊版程式碼。
- **F17** 試聽片段（`freeTrialInfo != null`）會被當成完整歌曲回傳；API 在什麼情況下回試聽網址還沒實測過。出處：`legacy:lib/data/sources/netease_source.dart:139-150`。可信度：舊版程式碼（觸發條件未驗）。
- **F18** eapi 回的串流網址是 `http://`：Android 要 `usesCleartextTraffic`，Apple 要 `NSAllowsArbitraryLoadsForMedia`。出處：`legacy:android/app/src/main/AndroidManifest.xml:33-40`。可信度：舊版程式碼。
- **F19**【待重驗】QR 登入走 weapi（兩層 AES-128-CBC 加不帶 padding 的 RSA），帶固定的匿名 cookie 偽裝 Windows 客戶端；eapi、weapi 兩套加密並存；搜尋用明文 `/api/*`。出處：`docs/audit/accounts-network.md`。可信度：上一版文件。
