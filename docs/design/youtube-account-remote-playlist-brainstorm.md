# YouTube 帳號管理 & 遠端操作 — 需求探索文檔

## 1. 目標

為 FMP 添加 YouTube 帳號登錄能力，並基於登錄態實現遠端播放列表操作。
要求：開箱即用，用戶登錄後即可使用，無需設置 API Key 或 OAuth Client ID。

## 2. 核心挑戰

### 2.1 Google 封殺 WebView 登錄

與 Bilibili 不同，Google 自 2021 年起全面封殺嵌入式 WebView 中的登錄：

| 平台 | 檢測方式 | 結果 |
|------|---------|------|
| Android WebView | UA 含 `;wv` 或 `Version/X.X` | `403 disallowed_useragent` |
| iOS WKWebView | UA 缺少 `Safari` token | `403 disallowed_useragent` |
| CEF/Electron | 嵌入式瀏覽器特徵 | `403 disallowed_useragent` |
| Windows WebView2 | 可能被檢測（Edge 內核） | 不確定，需測試 |

**結論：不能直接複製 Bilibili 的 WebView 登錄方案。**

### 2.2 YouTube API 認證體系

YouTube 有兩套完全獨立的 API：

| API | 認證方式 | 適用場景 |
|-----|---------|---------|
| YouTube Data API v3 | OAuth2 Bearer Token + API Key | 官方第三方應用（需 Google Cloud 項目） |
| InnerTube API（內部） | Session Cookies 或 TV OAuth2 | yt-dlp、YouTube.js、NewPipe 等 |

FMP 已使用 InnerTube API（`youtube_source.dart`），因此應繼續使用 InnerTube + Cookie/Token 認證。

### 2.3 Cookie 有效期對比

| 平台 | Cookie 有效期 | 刷新機制 |
|------|-------------|---------|
| Bilibili | ~1 個月 | RSA-OAEP 加密刷新流程 |
| YouTube | ~2 年 | 無需主動刷新，除非用戶登出 |

YouTube Cookie 壽命遠長於 Bilibili，認證維護成本更低。

---

## 3. 登錄方案分析

### 方案 A：WebView + UA 偽裝（推薦 Android）

**原理：** 使用 `flutter_inappwebview`，但修改 User-Agent 去除 WebView 標記，偽裝為普通 Chrome 瀏覽器。

**Android 實現：**
```dart
InAppWebView(
  initialUrlRequest: URLRequest(
    url: WebUri('https://accounts.google.com/ServiceLogin?service=youtube&continue=https://www.youtube.com'),
  ),
  initialSettings: InAppWebViewSettings(
    // 關鍵：使用純 Chrome UA，不含 ;wv 標記
    userAgent: 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.6261.64 Mobile Safari/537.36',
    // 啟用 JavaScript
    javaScriptEnabled: true,
    // 啟用 DOM Storage（Google 登錄需要）
    domStorageEnabled: true,
  ),
)
```

**Windows 實現：**
- WebView2（Edge 內核）可能不被 Google 視為嵌入式瀏覽器
- 需要實際測試確認

**Cookie 提取：**
```dart
// 登錄成功後（URL 跳轉到 youtube.com）
final cookieManager = CookieManager.instance();
final cookies = await cookieManager.getCookies(
  url: WebUri('https://www.youtube.com'),
);
// 提取關鍵 cookies: SID, HSID, SSID, APISID, SAPISID,
// __Secure-1PSID, __Secure-3PSID, __Secure-1PAPISID, __Secure-3PAPISID,
// LOGIN_INFO
```

| 優點 | 缺點 |
|------|------|
| UX 最佳（與 Bilibili 一致） | Google 可能更新檢測邏輯 |
| 用戶熟悉的登錄流程 | 違反 Google 政策（灰色地帶） |
| 可獲取完整 Cookie（所有 InnerTube 功能） | 需要持續維護 UA 字符串 |
| Windows WebView2 可能天然不被封殺 | Android 上風險較高 |

**風險評估：** 中等。許多開源項目仍在使用此方法，但 Google 可能隨時加強檢測。

### 方案 B：YouTube TV OAuth 設備碼流程

**原理：** 使用 YouTube TV 應用的公開 OAuth 客戶端憑據，通過設備碼流程認證。

**已知 TV 客戶端憑據（公開，多個開源項目使用）：**
```
client_id: 861556708454-d6dlm3lh05idd8npek18k6be8ba3oc68.apps.googleusercontent.com
client_secret: SboVhoG9s0rNafixCSGGKXAT
```

**流程：**
```
1. POST https://oauth2.googleapis.com/device/code
   body: { client_id, scope: "https://www.googleapis.com/auth/youtube" }
   → 返回 device_code, user_code, verification_url

2. 顯示給用戶：
   「請訪問 https://www.google.com/device 並輸入代碼：XXXX-XXXX」

3. 輪詢 POST https://oauth2.googleapis.com/token
   body: { client_id, client_secret, device_code, grant_type: "urn:ietf:params:oauth:grant_type:device_code" }
   → 用戶授權後返回 access_token + refresh_token

4. Token 自動刷新：
   POST https://oauth2.googleapis.com/token
   body: { client_id, client_secret, refresh_token, grant_type: "refresh_token" }
```

| 優點 | 缺點 |
|------|------|
| 完全合規，不違反 Google 政策 | 只能使用 TV InnerTube 客戶端 |
| 開箱即用，無需 API Key | Google 可能撤銷公開的 TV 憑據 |
| UX 乾淨（顯示代碼，用戶在手機/電腦授權） | TV 客戶端的播放列表管理功能可能受限 |
| Token 可自動刷新（refresh_token） | 2024 年底 Google 已限制此方式只能用 TV 客戶端 |
| 不需要 WebView | 部分 InnerTube 端點可能不支持 TV 客戶端 |

**風險評估：** 中等。Google 可能撤銷公開憑據，且 TV 客戶端功能受限。

### 方案 C：手動 Cookie 粘貼

**原理：** 用戶在瀏覽器中登錄 YouTube，從 DevTools 複製 Cookie，粘貼到 App 中。

**流程：**
```
1. App 顯示教程：「在瀏覽器中打開 youtube.com 並登錄」
2. 「按 F12 打開開發者工具 → Network → 刷新頁面」
3. 「點擊任意請求 → 複製 Cookie 標頭值」
4. 「粘貼到下方輸入框」
```

| 優點 | 缺點 |
|------|------|
| 100% 可靠，不受 Google 政策影響 | UX 極差，技術門檻高 |
| 獲取完整 Cookie | 用戶需要懂 DevTools |
| 無任何風險 | 手機端幾乎不可能操作 |

**風險評估：** 低風險，但 UX 不可接受作為主要方案。

### 方案 D：混合方案（推薦）

**結合方案 A + B + C，根據平台和情況選擇最佳路徑：**

```
┌─────────────────────────────────────────────┐
│           YouTube 登錄頁面                    │
│                                             │
│  ┌─ Tab 1: 網頁登錄（推薦）──────────────┐  │
│  │                                        │  │
│  │  [WebView - UA 偽裝]                   │  │
│  │  accounts.google.com → youtube.com     │  │
│  │  登錄成功後自動提取 Cookie              │  │
│  │                                        │  │
│  │  ⚠ 如果 Google 封殺，自動降級到 Tab 2  │  │
│  └────────────────────────────────────────┘  │
│                                             │
│  ┌─ Tab 2: 設備碼登錄 ──────────────────┐  │
│  │                                        │  │
│  │  請訪問 google.com/device              │  │
│  │  輸入代碼：ABCD-EFGH                   │  │
│  │                                        │  │
│  │  [在瀏覽器中打開]  [重新生成]           │  │
│  │                                        │  │
│  │  狀態：等待授權...                      │  │
│  └────────────────────────────────────────┘  │
│                                             │
│  ┌─ Tab 3: Cookie 粘貼（進階）───────────┐  │
│  │                                        │  │
│  │  [查看教程]                             │  │
│  │  ┌──────────────────────────────┐      │  │
│  │  │ 粘貼 Cookie 字符串...        │      │  │
│  │  └──────────────────────────────┘      │  │
│  │  [確認登錄]                             │  │
│  └────────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

**推薦優先級：**
1. **WebView 登錄**（Android + Windows）— 最佳 UX，與 Bilibili 一致
2. **設備碼登錄** — WebView 被封殺時的備選
3. **Cookie 粘貼** — 最後手段，面向進階用戶

---

## 4. InnerTube 認證技術細節

### 4.1 Cookie 認證（方案 A/C 使用）

**必需的 Cookie：**
```
SID, HSID, SSID, APISID, SAPISID
__Secure-1PSID, __Secure-3PSID
__Secure-1PAPISID, __Secure-3PAPISID
LOGIN_INFO, VISITOR_INFO1_LIVE
```

**SAPISIDHASH 算法（認證請求頭）：**
```dart
String generateSapisidHash(String sapisid, {String? datasyncId}) {
  final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final origin = 'https://www.youtube.com';

  // 基礎格式（讀取操作足夠）
  String input = '$timestamp $sapisid $origin';

  // 帶 DATASYNC_ID（寫入操作需要，如播放列表管理）
  if (datasyncId != null) {
    input = '$datasyncId $timestamp $sapisid $origin';
  }

  final hash = sha1.convert(utf8.encode(input)).toString();
  return '$timestamp\_$hash';
}

// 請求頭設置
headers['Authorization'] = 'SAPISIDHASH ${sapisidHash}_u';
headers['Cookie'] = cookieString;
headers['X-Origin'] = 'https://www.youtube.com';
```

**DATASYNC_ID 獲取：**
- 從 YouTube 頁面的 `ytcfg.data_.DATASYNC_ID` 提取
- 格式如 `AKreu9sXXXXXX||`，取 `||` 前的部分
- 登錄後首次訪問 youtube.com 時提取並緩存

### 4.2 TV OAuth 認證（方案 B 使用）

```dart
// InnerTube 請求頭
headers['Authorization'] = 'Bearer $accessToken';

// InnerTube context（必須使用 TV 客戶端）
final context = {
  'client': {
    'clientName': 'TVHTML5',
    'clientVersion': '7.20240813.07.00',
  }
};
```

### 4.3 InnerTube 播放列表管理端點

| 操作 | 端點 | 方法 | 說明 |
|------|------|------|------|
| 獲取用戶播放列表 | `/youtubei/v1/browse` | POST | `browseId: "FElibrary"` 或 `"FEmusic_liked_playlists"` |
| 獲取喜歡的影片 | `/youtubei/v1/browse` | POST | `browseId: "VLLL"` |
| 獲取播放列表內容 | `/youtubei/v1/browse` | POST | `browseId: "VL{playlistId}"` |
| 添加到播放列表 | `/youtubei/v1/browse/edit_playlist` | POST | `ACTION_ADD_VIDEO` |
| 從播放列表移除 | `/youtubei/v1/browse/edit_playlist` | POST | `ACTION_REMOVE_VIDEO`（需 `setVideoId`） |
| 創建播放列表 | `/youtubei/v1/playlist/create` | POST | title + videoIds |
| 刪除播放列表 | `/youtubei/v1/playlist/delete` | POST | playlistId |
| 觀看歷史 | `/youtubei/v1/browse` | POST | `browseId: "FEhistory"` |

**添加到播放列表 payload：**
```json
{
  "playlistId": "PLxxxxxxxx",
  "actions": [
    { "action": "ACTION_ADD_VIDEO", "addedVideoId": "dQw4w9WgXcQ" }
  ]
}
```

**從播放列表移除 payload：**
```json
{
  "playlistId": "PLxxxxxxxx",
  "actions": [
    { "action": "ACTION_REMOVE_VIDEO", "setVideoId": "XXXXXXXXXX" }
  ]
}
```
> 注意：`setVideoId` ≠ `videoId`。它是該影片在播放列表中的唯一實例 ID，需從 `get_playlist()` 響應中獲取。

---

## 5. 憑據存儲設計

### 5.1 YouTubeCredentials 模型

```dart
/// YouTube 憑據結構（JSON 序列化存儲到 flutter_secure_storage）
class YouTubeCredentials {
  // === Cookie 認證（方案 A/C）===
  final String? cookieString;       // 完整 Cookie 字符串
  final String? sapisid;            // SAPISID（用於生成 SAPISIDHASH）
  final String? secure3Papisid;     // __Secure-3PAPISID
  final String? datasyncId;         // DATASYNC_ID（用於寫入操作）

  // === TV OAuth 認證（方案 B）===
  final String? accessToken;
  final String? refreshToken;
  final DateTime? tokenExpiry;

  // === 通用 ===
  final String authMethod;          // 'cookie' | 'tv_oauth' | 'cookie_paste'
  final DateTime savedAt;

  /// 是否使用 Cookie 認證
  bool get isCookieAuth => authMethod == 'cookie' || authMethod == 'cookie_paste';

  /// 是否使用 TV OAuth
  bool get isTvOAuth => authMethod == 'tv_oauth';

  /// Token 是否過期（TV OAuth）
  bool get isTokenExpired => tokenExpiry != null && DateTime.now().isAfter(tokenExpiry!);
}
```

### 5.2 存儲 Key

```dart
static const String _storageKey = 'account_youtube_credentials';
```

與 Bilibili 一致，敏感數據存 `flutter_secure_storage`，用戶信息存 Isar `Account`。

---

## 6. 服務層設計

### 6.1 文件結構（新增）

```
lib/services/account/
├── account_service.dart                 # 已有：抽象接口
├── youtube_account_service.dart         # 新增：YouTube 帳號服務
├── youtube_credentials.dart             # 新增：憑據模型
├── youtube_auth_interceptor.dart        # 新增：Dio 攔截器
└── youtube_playlist_service.dart        # 新增：播放列表 CRUD

lib/ui/pages/settings/
├── account_management_page.dart         # 修改：啟用 YouTube 卡片
└── youtube_login_page.dart              # 新增：YouTube 登錄頁
```

### 6.2 YouTubeAccountService

```dart
class YouTubeAccountService extends AccountService with Logging {
  final Dio _dio;
  final FlutterSecureStorage _secureStorage;
  final Isar _isar;

  @override
  SourceType get platform => SourceType.youtube;

  // ===== WebView Cookie 登錄 =====

  /// WebView 登錄完成後，從 Cookie 初始化
  Future<void> loginWithCookies(List<Cookie> cookies);

  /// 從 YouTube 頁面提取 DATASYNC_ID
  Future<String?> extractDatasyncId();

  // ===== TV OAuth 設備碼登錄 =====

  /// 生成設備碼
  Future<DeviceCodeData> generateDeviceCode();

  /// 輪詢授權狀態
  Stream<DeviceCodePollResult> pollDeviceCodeStatus(String deviceCode);

  /// 刷新 Access Token
  Future<bool> refreshAccessToken();

  // ===== Cookie 粘貼登錄 =====

  /// 從粘貼的 Cookie 字符串登錄
  Future<void> loginWithCookieString(String cookieString);

  // ===== 認證管理 =====

  /// 獲取認證請求頭（根據認證方式自動選擇）
  Future<Map<String, String>> getAuthHeaders();

  /// 獲取 InnerTube context（根據認證方式選擇客戶端）
  Map<String, dynamic> getInnerTubeContext();

  // ===== 用戶信息 =====

  /// 獲取用戶信息（通過 InnerTube /account/account_menu）
  Future<void> fetchAndUpdateUserInfo();
}
```

### 6.3 YouTubePlaylistService

```dart
class YouTubePlaylistService with Logging {
  final YouTubeAccountService _accountService;
  final Dio _dio;

  /// 獲取用戶的播放列表列表
  Future<List<YouTubePlaylistInfo>> getUserPlaylists();

  /// 獲取「喜歡的影片」列表
  Future<List<Track>> getLikedVideos({int limit = 50});

  /// 添加影片到播放列表
  Future<void> addVideoToPlaylist({
    required String playlistId,
    required String videoId,
  });

  /// 從播放列表移除影片
  /// 需要 setVideoId（從播放列表內容中獲取）
  Future<void> removeVideoFromPlaylist({
    required String playlistId,
    required String setVideoId,
  });

  /// 創建新播放列表
  Future<String> createPlaylist({
    required String title,
    String? description,
    bool isPrivate = false,
    List<String> videoIds = const [],
  });

  /// 檢查影片是否在播放列表中
  /// （需要先獲取播放列表內容，無直接 API）
  Future<bool> isVideoInPlaylist(String playlistId, String videoId);
}

class YouTubePlaylistInfo {
  final String playlistId;
  final String title;
  final String? thumbnailUrl;
  final int videoCount;
  final bool isPrivate;
}
```

### 6.4 YouTubeAuthInterceptor

```dart
class YouTubeAuthInterceptor extends Interceptor {
  final YouTubeAccountService _accountService;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final authHeaders = await _accountService.getAuthHeaders();
    options.headers.addAll(authHeaders);
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    // YouTube 認證錯誤通常返回 401 或特定 error code
    if (_isAuthError(err.response)) {
      if (_accountService.credentials?.isTvOAuth == true) {
        // TV OAuth: 嘗試刷新 token
        final refreshed = await _accountService.refreshAccessToken();
        if (refreshed) {
          final retryResponse = await _dio.fetch(err.requestOptions);
          return handler.resolve(retryResponse);
        }
      }
      // Cookie 認證過期：無法自動刷新，需要重新登錄
    }
    handler.next(err);
  }
}
```

---

## 7. 與 Bilibili 方案的差異對比

| 項目 | Bilibili | YouTube |
|------|---------|---------|
| 登錄方式 | WebView（主）+ QR 碼（備） | WebView UA偽裝（主）+ 設備碼（備）+ Cookie粘貼（末） |
| Cookie 有效期 | ~1 個月 | ~2 年 |
| Cookie 刷新 | RSA-OAEP 加密流程 | 無需刷新（或 TV OAuth refresh_token） |
| 認證請求頭 | `Cookie: SESSDATA=xxx; bili_jct=xxx` | `Authorization: SAPISIDHASH xxx` + `Cookie: ...` |
| CSRF Token | `bili_jct` cookie | 不需要（InnerTube 用 session token） |
| 遠端操作 | 收藏夾 CRUD | 播放列表 CRUD |
| 「已存在」標記 | API `fav_state` 字段 | 需要先獲取播放列表內容比對 |
| 創建收藏夾/播放列表 | 支持 | 支持 |
| 批量操作 | `batch-del` API | 逐個 `ACTION_REMOVE_VIDEO` |

---

## 8. 遠端操作 UI 設計

### 8.1 添加到 YouTube 播放列表彈窗

```
┌─────────────────────────────────────┐
│ ─── 拖拽指示條 ───                   │
│                                     │
│ 添加到 YouTube 播放列表       [✕]   │
│                                     │
│ ┌─────────────────────────────┐     │
│ │ [封面] 影片標題              │     │
│ │        頻道名稱              │     │
│ └─────────────────────────────┘     │
│                                     │
│ ─── 播放列表 (loading...) ───       │
│                                     │
│ ┌─────────────────────────────┐     │
│ │ [🎵] 喜歡的影片 (1,234) [✓] │ ← 已存在
│ │ [📁] 我的音樂 (42)      [ ] │     │
│ │ [📁] 收藏 (85)          [ ] │     │
│ │ [+] 創建新播放列表           │     │
│ └─────────────────────────────┘     │
│                                     │
│ ┌─────────────────────────────┐     │
│ │        [確認] 添加到 1 個    │     │
│ └─────────────────────────────┘     │
└─────────────────────────────────────┘
```

### 8.2 菜單集成

與 Bilibili 完全對稱：
- YouTube 歌曲顯示「添加到 YouTube 播放列表」
- 導入的 YouTube 歌單詳情頁顯示「從 YouTube 播放列表移除」
- 多選模式同樣支持

### 8.3 統一遠端操作入口

可以考慮將 Bilibili 和 YouTube 的遠端操作統一：

```dart
// 根據 track.sourceType 自動選擇
void showAddToRemotePlaylistDialog(Track track) {
  switch (track.sourceType) {
    case SourceType.bilibili:
      showBilibiliAddToFavoritesDialog(track);
    case SourceType.youtube:
      showYouTubeAddToPlaylistDialog(track);
  }
}
```

菜單項可以統一為「添加到遠端播放列表」，自動根據歌曲來源選擇對應平台。

---

## 9. 關鍵問題待確認

### Q1：WebView UA 偽裝是否可行？
- 需要在 Android 和 Windows 上實際測試
- Android 風險較高（Google 持續加強檢測）
- Windows WebView2 可能天然不被封殺
- **建議：先實現並測試，如果被封殺再降級到設備碼方案**

### Q2：TV OAuth 的播放列表管理功能是否完整？
- TV 客戶端（TVHTML5）是否支持 `edit_playlist` 端點？
- 是否能獲取完整的用戶播放列表？
- **需要實際測試確認**

### Q3：是否需要 DATASYNC_ID？
- 讀取操作（獲取播放列表）可能不需要
- 寫入操作（添加/移除）可能需要
- 如果 WebView 登錄可行，可以在登錄後從頁面提取
- 如果使用 TV OAuth，可能不需要（使用 Bearer token）

### Q4：「已存在」標記如何實現？
- YouTube 沒有像 Bilibili 那樣的 `fav_state` 字段
- 需要先獲取每個播放列表的內容，然後本地比對
- 對於大播放列表，這可能很慢
- **方案：只檢查前 N 個播放列表，或使用本地緩存**

### Q5：登錄方案的優先級？
- 選項 1：只實現 WebView（最簡單，但有風險）
- 選項 2：只實現設備碼（最安全，但功能可能受限）
- 選項 3：混合方案（最完整，但開發量大）
- **建議：先實現 WebView，如果被封殺再加設備碼**

---

## 10. 實現順序建議

### Phase 1：基礎設施 + WebView 登錄
1. `YouTubeCredentials` 模型
2. `YouTubeAccountService`（WebView Cookie 登錄）
3. `YouTubeAuthInterceptor`
4. `YouTubeLoginPage`（WebView Tab）
5. 啟用 `AccountManagementPage` 的 YouTube 卡片
6. Provider 層（`youtubeAccountProvider` 等）

### Phase 2：遠端播放列表操作
1. `YouTubePlaylistService`（獲取列表、添加、移除、創建）
2. `AddToYouTubePlaylistDialog`
3. 菜單集成（與 Bilibili 對稱）
4. 操作後刷新邏輯

### Phase 3：備選登錄方式
1. 設備碼登錄（Tab 2）
2. Cookie 粘貼登錄（Tab 3）
3. 認證方式自動降級邏輯

### Phase 4：增強功能
1. 喜歡的影片列表瀏覽
2. 觀看歷史
3. 訂閱頻道列表
4. 統一遠端操作入口（Bilibili + YouTube）
