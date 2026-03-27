# 網易雲音樂直接音源集成 — 設計文檔

> **版本**: 1.0
> **日期**: 2026-03-26
> **範圍**: Phase 1 (網易雲音樂)，含導入/播放/歌詞/帳號重構
> **前置條件**: Phase 2 (QQ音樂) 按相同模式實現；Phase 2 完成後移除 `originalSongId` / `originalSource`

---

## 目錄

1. [概覽](#1-概覽)
2. [數據模型變更](#2-數據模型變更)
3. [加密層](#3-加密層)
4. [NeteaseSource — BaseSource 實現](#4-neteasesource--basesource-實現)
5. [異常處理](#5-異常處理)
6. [帳號服務](#6-帳號服務)
7. [導入功能重構](#7-導入功能重構)
8. [播放功能重構](#8-播放功能重構)
9. [歌詞系統適配](#9-歌詞系統適配)
10. [歌單封面重構](#10-歌單封面重構)
11. [UI 變更](#11-ui-變更)
12. [依賴包](#12-依賴包)
13. [文件清單](#13-文件清單)
14. [實施階段](#14-實施階段)
15. [數據庫遷移](#15-數據庫遷移)

---

## 1. 概覽

### 1.1 目標

將網易雲音樂作為 **直接音源** 集成到 FMP，與 Bilibili / YouTube 並列。用戶可以：

- 直接播放網易雲音樂歌曲（非通過搜索轉為其他平台視頻）
- 導入網易雲歌單並保留原始歌曲 ID
- 搜索網易雲音樂
- 使用 QR 碼或 WebView (Android) 登入網易雲帳號
- 下載網易雲歌曲

### 1.2 架構原則

- **統一接口**：NeteaseSource 實現 `BaseSource` 抽象類，與 BilibiliSource / YouTubeSource 完全對等
- **不再有 auth 重試**：是否使用登入狀態完全由用戶設定控制，移除 `withAuthRetry` 邏輯
- **簡潔統一**：所有音源共用相同的導入、播放、下載、刷新流程

### 1.3 系統架構圖

```
┌─────────────────────────────────────────────────────────────┐
│                         UI Layer                             │
│  SearchPage  PlaylistDetail  PlayerPage  Settings  Login     │
└────────────────────────┬────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────┐
│                    Provider Layer                             │
│  sourceManagerProvider  accountProviders  settingsProvider    │
└────────────────────────┬────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────┐
│                   Service Layer                              │
│  AudioController  QueueManager  ImportService  DownloadSvc   │
│  NeteaseAccountService  LyricsAutoMatchService               │
└────────────────────────┬────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────┐
│                    Source Layer                               │
│  BilibiliSource  YouTubeSource  NeteaseSource (NEW)          │
│  NeteaseApiException  NeteaseCrypto                          │
└──────────────────────────────────────────────────────────────┘
```

---

## 2. 數據模型變更

### 2.1 SourceType 枚舉 (`lib/data/models/track.dart`)

```dart
enum SourceType {
  bilibili,
  youtube,
  netease;   // 新增

  String get displayName {
    switch (this) {
      case SourceType.bilibili: return t.importPlatform.bilibili;
      case SourceType.youtube: return t.importPlatform.youtube;
      case SourceType.netease: return t.importPlatform.netease;
    }
  }
}
```

### 2.2 Track 模型 (`lib/data/models/track.dart`)

| 變更 | 字段 | 類型 | 默認值 | 說明 |
|------|------|------|--------|------|
| **新增** | `isVip` | `bool` | `false` | VIP 歌曲標記 |

網易雲歌曲的 `sourceId` 直接存儲網易雲歌曲 ID（如 `"33894312"`），`sourceType = SourceType.netease`。

`originalSongId` / `originalSource` 暫時保留（Phase 2 QQ音樂完成後移除）。

### 2.3 Playlist 模型 (`lib/data/models/playlist.dart`)

| 變更 | 字段 | 類型 | 默認值 | 說明 |
|------|------|------|--------|------|
| **新增** | `ownerName` | `String?` | `null` | 歌單所有者暱稱 |
| **新增** | `ownerUserId` | `String?` | `null` | 歌單所有者平台 ID |
| **新增** | `useAuthForRefresh` | `bool` | `false` | 刷新時使用登入狀態 |

### 2.4 Settings 模型 (`lib/data/models/settings.dart`)

| 變更 | 字段 | 類型 | 默認值 | 說明 |
|------|------|------|--------|------|
| **新增** | `useBilibiliAuthForPlay` | `bool` | `false` | Bilibili 播放用登入態 |
| **新增** | `useYoutubeAuthForPlay` | `bool` | `false` | YouTube 播放用登入態 |
| **新增** | `useNeteaseAuthForPlay` | `bool` | `true` | 網易雲播放用登入態 |

> Phase 2 新增 `useQqmusicAuthForPlay = true`。

**便捷方法**：
```dart
/// 獲取指定音源的播放登入態設定
bool useAuthForPlay(SourceType sourceType) {
  switch (sourceType) {
    case SourceType.bilibili: return useBilibiliAuthForPlay;
    case SourceType.youtube: return useYoutubeAuthForPlay;
    case SourceType.netease: return useNeteaseAuthForPlay;
  }
}
```

新增網易雲音頻流配置字段：
```dart
/// 網易雲流優先級（CSV: "audioOnly"）
/// 網易雲只有 audioOnly，但保持統一模式
String neteaseStreamPriority = 'audioOnly';
```

### 2.5 PlaylistParseResult 擴展 (`lib/data/sources/base_source.dart`)

```dart
class PlaylistParseResult {
  final String title;
  final String? description;
  final String? coverUrl;
  final List<Track> tracks;
  final int totalCount;
  final String sourceUrl;
  final String? ownerName;     // 新增
  final String? ownerUserId;   // 新增

  const PlaylistParseResult({
    required this.title,
    this.description,
    this.coverUrl,
    required this.tracks,
    required this.totalCount,
    required this.sourceUrl,
    this.ownerName,             // 新增
    this.ownerUserId,           // 新增
  });
}
```

### 2.6 Account 模型

無需修改。`Account.platform` 已使用 `SourceType`，新增 `netease` 後自動支持。

---

## 3. 加密層

### 3.1 文件：`lib/core/utils/netease_crypto.dart`

實現 weapi 和 eapi 兩種加密模式。

### 3.2 weapi 加密算法

```
1. JSON.encode(data)
2. 生成隨機 16 字符密鑰 (base62 字符集)
3. Layer 1: AES-128-CBC(plaintext, presetKey="0CoJUm6Qyw8W8jud", IV="0102030405060708") → base64
4. Layer 2: AES-128-CBC(layer1, randomKey, IV="0102030405060708") → base64 = params
5. RSA: reversed(randomKey) ^ 65537 mod modulus → 256 位 hex = encSecKey
6. POST body: params={base64}&encSecKey={hex}
```

### 3.3 eapi 加密算法

```
1. message = "nobody{url}use{text}md5forencrypt"
2. digest = MD5(message)
3. payload = "{url}-36cd479b6b5-{text}-36cd479b6b5-{digest}"
4. AES-128-ECB(payload, key="e82ckenh8dichen8") → uppercase hex = params
```

### 3.4 依賴

| Package | 用途 | 狀態 |
|---------|------|------|
| `encrypt` | AES-CBC / AES-ECB | **需新增** |
| `crypto` | MD5 | 已有 |

RSA 用原生 `BigInt.modPow()`，不需要 `pointycastle`（雖然已有但不需要用）。

### 3.5 密鑰常量

```dart
class NeteaseCrypto {
  static const _presetKey = '0CoJUm6Qyw8W8jud';
  static const _iv = '0102030405060708';
  static const _eapiKey = 'e82ckenh8dichen8';
  static const _base62 = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  static const _rsaModulus = '00e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7b725152b3ab17a876aea8a5aa76d2e417629ec4ee341f56135fccf695280104e0312ecbda92557c93870114af6c9d05c4f7f0c3685b7a46bee255932575cce10b424d813cfe4875d3e82047b97ddef52741d546b8e289dc6935b3ece0462db0a22b8e7';
  static const _rsaExponent = '010001';

  /// weapi 加密 → {params, encSecKey}
  static Map<String, String> weapi(Map<String, dynamic> data);

  /// eapi 加密 → {params}
  static String eapi(String url, Map<String, dynamic> data);

  /// eapi 解密
  static Map<String, dynamic> eapiDecrypt(String encrypted);
}
```

---

## 4. NeteaseSource — BaseSource 實現

### 4.1 文件：`lib/data/sources/netease_source.dart`

### 4.2 類結構

```dart
class NeteaseSource extends BaseSource {
  final Dio _dio;

  NeteaseSource({Dio? dio}) : _dio = dio ?? _createDio();

  @override
  SourceType get sourceType => SourceType.netease;

  static Dio _createDio() => Dio(BaseOptions(
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) ...',
      'Referer': 'https://music.163.com',
      'Origin': 'https://music.163.com',
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    connectTimeout: AppConstants.networkConnectTimeout,
    receiveTimeout: AppConstants.networkReceiveTimeout,
  ));

  void dispose() => _dio.close();
}
```

### 4.3 接口實現

#### parseId / canHandle / isPlaylistUrl

```dart
@override
String? parseId(String url) {
  // 匹配 music.163.com/song?id=xxx 或 /song/xxx
  final match = RegExp(r'music\.163\.com.*?(?:song[?/].*?|id=)(\d+)').firstMatch(url);
  return match?.group(1);
}

@override
bool isValidId(String id) => RegExp(r'^\d+$').hasMatch(id);

@override
bool isPlaylistUrl(String url) {
  return RegExp(r'music\.163\.com.*?playlist[?/]').hasMatch(url) ||
         RegExp(r'163cn\.tv').hasMatch(url);
}
```

#### getTrackInfo

```dart
@override
Future<Track> getTrackInfo(String sourceId, {Map<String, String>? authHeaders}) async {
  // POST /weapi/v3/song/detail
  // Body: {c: '[{"id":"$sourceId"}]', ids: '[$sourceId]'}
  // 使用 NeteaseCrypto.weapi() 加密
  //
  // 解析 privilege 判斷 VIP:
  //   fee == 1 || fee == 4 → isVip = true
  //   st == -200 → isAvailable = false
  //
  // 返回 Track:
  //   sourceId = songId.toString()
  //   sourceType = SourceType.netease
  //   title = song['name']
  //   artist = ar.map(a => a['name']).join(', ')
  //   thumbnailUrl = al['picUrl']
  //   durationMs = song['dt']
  //   isVip = (privilege.fee == 1 || privilege.fee == 4)
}
```

#### getAudioStream

```dart
@override
Future<AudioStreamResult> getAudioStream(
  String sourceId, {
  AudioStreamConfig config = AudioStreamConfig.defaultConfig,
  Map<String, String>? authHeaders,
}) async {
  // POST /weapi/song/enhance/player/url/v1
  // Body: {id: sourceId, level: _mapQualityLevel(config.qualityLevel)}
  // Cookie header: authHeaders?['Cookie']
  //
  // level 映射:
  //   AudioQualityLevel.high   → 'exhigh'   (320kbps)
  //   AudioQualityLevel.medium → 'higher'   (192kbps)
  //   AudioQualityLevel.low    → 'standard' (128kbps)
  //
  // 返回值:
  //   data[0]['url'] — 可能為 null (VIP / 無版權)
  //   data[0]['br']  — 碼率 (bps)
  //   data[0]['type'] — 格式 (mp3/m4a/flac)
  //   data[0]['expi'] — 過期時間 (秒)
  //
  // url 為 null 時: 拋出 NeteaseApiException(code: 'vip_required' 或 'unavailable')
  //
  // 返回 AudioStreamResult:
  //   url = data[0]['url']
  //   bitrate = data[0]['br']
  //   container = data[0]['type']
  //   codec = 'aac' (mp3/m4a) 或 'flac'
  //   streamType = StreamType.audioOnly
}
```

#### search

```dart
@override
Future<SearchResult> search(
  String query, {
  int page = 1,
  int pageSize = 20,
  SearchOrder order = SearchOrder.relevance,
}) async {
  // POST /weapi/cloudsearch/get/web
  // Body: {s: query, type: 1, limit: pageSize, offset: (page-1)*pageSize}
  //
  // 返回 SearchResult:
  //   tracks: 解析 result.songs 列表
  //   totalCount: result.songCount
  //   hasMore: (page * pageSize) < totalCount
}
```

#### parsePlaylist

```dart
@override
Future<PlaylistParseResult> parsePlaylist(
  String playlistUrl, {
  int page = 1,
  int pageSize = 20,
  Map<String, String>? authHeaders,
}) async {
  // 1. 提取歌單 ID（複用現有 NeteasePlaylistSource 的正則邏輯）
  // 2. POST /weapi/v3/playlist/detail  Body: {id: playlistId, n: 0}
  //    → 獲取元數據 + trackIds 全列表（不含 track 詳情）
  // 3. 根據 trackIds 分批獲取歌曲詳情（每批 400）
  //    POST /weapi/v3/song/detail  Body: {c: '[{id:xxx},{id:xxx},...]'}
  // 4. 解析 privilege 設置 isVip
  //
  // 返回 PlaylistParseResult:
  //   title = playlist['name']
  //   description = playlist['description']
  //   coverUrl = playlist['coverImgUrl']     ← 平台封面
  //   ownerName = playlist['creator']['nickname']
  //   ownerUserId = playlist['creator']['userId'].toString()
  //   tracks = 全部歌曲 (Track 列表)
  //   totalCount = playlist['trackCount']
  //   sourceUrl = playlistUrl
}
```

#### refreshAudioUrl

```dart
@override
Future<Track> refreshAudioUrl(Track track, {Map<String, String>? authHeaders}) async {
  final result = await getAudioStream(track.sourceId, authHeaders: authHeaders);
  track.audioUrl = result.url;
  track.audioUrlExpiry = DateTime.now().add(const Duration(minutes: 20));
  track.updatedAt = DateTime.now();
  return track;
}
```

### 4.4 HTTP Headers

所有請求需攜帶：
```
User-Agent: Mozilla/5.0 ...
Referer: https://music.163.com
Origin: https://music.163.com
```

帶 auth 時額外注入：
```
Cookie: MUSIC_U=xxx; __csrf=xxx
```

`csrf_token` 參數需與 `__csrf` Cookie 值一致。

### 4.5 音頻 URL 過期策略

網易雲音頻 URL 返回 `expi` 字段（秒數），典型值 1200 秒 (20 分鐘)。設置 `audioUrlExpiry = now + expi * 0.8`（提前 20% 刷新）。

---

## 5. 異常處理

### 5.1 文件：`lib/data/sources/netease_exception.dart`

```dart
class NeteaseApiException extends SourceApiException {
  /// 網易雲 API 返回的數字碼（如 200, -460, -462, 403）
  final int numericCode;

  NeteaseApiException({
    required this.numericCode,
    required String message,
  }) : super(
    code: _mapCode(numericCode),
    message: message,
    sourceType: SourceType.netease,
  );

  static String _mapCode(int numericCode) {
    switch (numericCode) {
      case -460: return 'rate_limited';
      case -462: return 'rate_limited';
      case 301:  return 'requires_login';
      case 403:  return 'forbidden';
      case -200: return 'unavailable';
      case -2:   return 'unavailable';
      default:   return 'api_error';
    }
  }

  @override
  bool get isUnavailable => code == 'unavailable';
  @override
  bool get isRateLimited => code == 'rate_limited';
  @override
  bool get isGeoRestricted => false; // 網易雲無地域限制標記
  @override
  bool get requiresLogin => code == 'requires_login';
  @override
  bool get isNetworkError => code == 'network_error';
  @override
  bool get isTimeout => code == 'timeout';
  @override
  bool get isPermissionDenied => code == 'forbidden';

  /// VIP 歌曲需付費
  bool get isVipRequired => numericCode == -10;
}
```

### 5.2 錯誤處理流程

```
NeteaseSource.getAudioStream()
  ├─ url == null && fee == 1/4 → NeteaseApiException(numericCode: -10, "VIP required")
  ├─ url == null && st == -200 → NeteaseApiException(numericCode: -200, "Unavailable")
  ├─ url == null (其他)        → NeteaseApiException(numericCode: -1, "No stream URL")
  ├─ code == 301               → NeteaseApiException(numericCode: 301, "Login required")
  └─ DioException              → NeteaseApiException(classifyDioError)

AudioController._handleSourceError()
  └─ catch (SourceApiException) → 統一錯誤處理（Toast + 跳過）
```

VIP 歌曲**不做特殊處理**：嘗試正常播放，失敗後進入標準錯誤流程（Toast + 跳過）。

---

## 6. 帳號服務

### 6.1 憑證模型：`lib/services/account/netease_credentials.dart`

```dart
class NeteaseCredentials {
  final String musicU;      // MUSIC_U cookie — 主要認證令牌
  final String csrf;        // __csrf cookie — CSRF 令牌
  final String? userId;     // 用戶 ID
  final DateTime savedAt;   // 保存時間

  NeteaseCredentials({
    required this.musicU,
    required this.csrf,
    this.userId,
    required this.savedAt,
  });

  factory NeteaseCredentials.fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJson();

  String toCookieString() =>
    'MUSIC_U=$musicU; __csrf=$csrf';
}
```

### 6.2 帳號服務：`lib/services/account/netease_account_service.dart`

```dart
class NeteaseAccountService extends AccountService with Logging {
  final Dio _dio;
  final FlutterSecureStorage _secureStorage;
  final Isar _isar;
  NeteaseCredentials? _cachedCredentials;

  static const String _storageKey = 'account_netease_credentials';
  static const String _apiBase = 'https://music.163.com';

  @override
  SourceType get platform => SourceType.netease;

  // ===== 登錄 =====

  /// WebView 登錄完成後，從 Cookie 初始化（僅 Android）
  Future<void> loginWithCookies({
    required String musicU,
    required String csrf,
  }) async;

  /// QR 碼登錄 - 生成 QR 碼
  /// POST /weapi/login/qrcode/unikey  Body: {type: 1}
  /// 返回 unikey，編碼為 URL: https://music.163.com/login?codekey={unikey}
  Future<QrCodeData> generateQrCode() async;

  /// QR 碼登錄 - 輪詢掃碼狀態
  /// POST /weapi/login/qrcode/client/login  Body: {type: 1, key: unikey}
  /// 800=過期, 801=等待, 802=已掃碼, 803=成功
  Stream<QrCodePollResult> pollQrCodeStatus(String qrcodeKey);

  // ===== 認證 =====

  /// 獲取認證 Cookie 字串（用於 HTTP 請求）
  Future<String?> getAuthCookieString() async;

  /// 獲取認證 Headers
  Future<Map<String, String>?> getAuthHeaders() async {
    final cookies = await getAuthCookieString();
    if (cookies == null) return null;
    return {'Cookie': cookies};
  }

  /// 獲取 CSRF Token（用於 weapi 請求的 csrf_token 參數）
  Future<String?> getCsrfToken() async;

  // ===== 帳號狀態 =====

  @override
  Future<bool> isLoggedIn() async;

  @override
  Future<Account?> getCurrentAccount() async;

  /// 檢查登錄狀態
  /// POST /weapi/w/nuser/account/get
  Future<Map<String, dynamic>?> checkLoginStatus() async;

  @override
  Future<void> logout() async;

  @override
  Future<bool> refreshCredentials() async => true; // MUSIC_U 有效期長，無需主動刷新

  @override
  Future<bool> needsRefresh() async => false;

  // ===== 用戶歌單 =====

  /// 獲取用戶歌單列表
  /// POST /weapi/user/playlist  Body: {uid: userId, limit: 30, offset: 0}
  Future<List<NeteasePlaylistInfo>> getUserPlaylists() async;
}
```

### 6.3 QR 碼登錄流程

```
┌──────────┐     ┌──────────────┐     ┌────────────────┐
│  App UI  │     │ AccountSvc   │     │ 網易雲 Server  │
└────┬─────┘     └──────┬───────┘     └───────┬────────┘
     │                  │                      │
     │  generateQr()    │                      │
     │─────────────────>│  POST /weapi/login/  │
     │                  │  qrcode/unikey       │
     │                  │─────────────────────>│
     │                  │<─────────────────────│ unikey
     │<─────────────────│                      │
     │  QR Code Image   │                      │
     │                  │                      │
     │  pollStatus()    │                      │
     │─────────────────>│  POST /weapi/login/  │
     │                  │  qrcode/client/login │
     │                  │─────────────────────>│
     │                  │<─────────────────────│ 801 (waiting)
     │  ... 每 3 秒 ... │                      │
     │                  │─────────────────────>│
     │                  │<─────────────────────│ 802 (scanned)
     │<─────────────────│                      │
     │  "已掃碼，待確認" │                      │
     │                  │─────────────────────>│
     │                  │<─────────────────────│ 803 + Set-Cookie
     │                  │                      │
     │                  │  提取 MUSIC_U, __csrf│
     │                  │  保存到 SecureStorage │
     │                  │  更新 Account (Isar) │
     │<─────────────────│                      │
     │  登錄成功         │                      │
```

### 6.4 登錄頁面：`lib/ui/pages/settings/netease_login_page.dart`

| 平台 | 登錄方式 |
|------|---------|
| Android | TabBar: WebView + QR Code |
| Windows / Desktop | 僅 QR Code |

WebView 載入 URL: `https://music.163.com/#/login`
監控 Cookie 變化，檢測 `MUSIC_U` 出現即為登錄成功。

### 6.5 Provider

```dart
// lib/providers/account_provider.dart 新增

final neteaseAccountServiceProvider = Provider<NeteaseAccountService>((ref) {
  final isar = ref.watch(isarInstanceProvider);
  return NeteaseAccountService(isar: isar);
});

final neteaseAccountProvider = StateNotifierProvider<AccountNotifier, Account?>((ref) {
  final isar = ref.watch(isarInstanceProvider);
  return AccountNotifier(isar: isar, platform: SourceType.netease);
});

final isNeteaseLoggedInProvider = Provider<bool>((ref) {
  return ref.watch(neteaseAccountProvider)?.isLoggedIn ?? false;
});
```

---

## 7. 導入功能重構

### 7.1 核心變更：移除 auth 重試

**刪除**：`withAuthRetry` / `withAuthRetryDirect`（`auth_retry_utils.dart` 中）

**保留並重命名**：`buildAuthHeaders` / `getAuthHeadersForPlatform` → 移至 `auth_headers_utils.dart`

擴展 `buildAuthHeaders` 支持 `SourceType.netease`：
```dart
Future<Map<String, String>?> buildAuthHeaders(
  SourceType platform, {
  BilibiliAccountService? bilibiliAccountService,
  YouTubeAccountService? youtubeAccountService,
  NeteaseAccountService? neteaseAccountService,  // 新增
}) async {
  switch (platform) {
    case SourceType.bilibili:
      final cookies = await bilibiliAccountService?.getAuthCookieString();
      if (cookies == null) return null;
      return {'Cookie': cookies};
    case SourceType.youtube:
      return await youtubeAccountService?.getAuthHeaders();
    case SourceType.netease:
      return await neteaseAccountService?.getAuthHeaders();
  }
}
```

### 7.2 ImportPlaylistDialog 改造

新增「使用登入狀態導入」開關：

```
┌─────────────────────────────────────────────┐
│ 導入歌單                                      │
│                                               │
│ [URL 輸入框]              [🎵 detected icon]  │
│ [歌單名稱（可選）]                             │
│                                               │
│ [搜索來源選擇]  ← 僅外部歌單顯示              │
│                                               │
│ ┌─ 使用登入狀態導入 ──────────── [  開關  ] ─┐ │
│ │ 對私人歌單或需要登入才能查看     │ │
│ │ 的內容，請開啟此選項                        │ │
│ └─────────────────────────────────────────── ┘ │
│                                               │
│         [取消]              [導入]             │
└─────────────────────────────────────────────┘
```

**邏輯**：
- 開關默認關閉
- 開啟時：`ImportService.importFromUrl(url, useAuth: true)`
- 導入成功後：`playlist.useAuthForRefresh = useAuth`

### 7.3 ImportService 改造

```dart
Future<ImportResult> importFromUrl(
  String url, {
  String? customName,
  int? refreshIntervalHours,
  bool notifyOnUpdate = true,
  bool useAuth = false,  // 新增
}) async {
  // ...
  // 根據 useAuth 決定 auth headers
  Map<String, String>? authHeaders;
  if (useAuth) {
    authHeaders = await _getAuthHeaders(source.sourceType);
  }

  final result = await source.parsePlaylist(url, authHeaders: authHeaders);

  // 保存歌單所有者信息
  playlist.ownerName = result.ownerName;
  playlist.ownerUserId = result.ownerUserId;
  playlist.useAuthForRefresh = useAuth;

  // 封面：使用平台封面（非第一首歌封面）
  if (!playlist.hasCustomCover && result.coverUrl != null) {
    playlist.coverUrl = result.coverUrl;
  }
  // ...
}
```

### 7.4 refreshPlaylist 改造

```dart
Future<ImportResult> refreshPlaylist(int playlistId) async {
  // ...
  // 根據 playlist.useAuthForRefresh 決定
  Map<String, String>? authHeaders;
  if (playlist.useAuthForRefresh) {
    authHeaders = await _getAuthHeaders(source.sourceType);
  }

  final result = await source.parsePlaylist(playlist.sourceUrl!, authHeaders: authHeaders);

  // 刷新封面
  if (!playlist.hasCustomCover && result.coverUrl != null) {
    playlist.coverUrl = result.coverUrl;
  }
  // ...
}
```

### 7.5 編輯歌單對話框 (`create_playlist_dialog.dart`)

新增「使用登入狀態刷新」開關（僅已導入歌單顯示）：

```dart
// 在 auto-refresh section 之前或之後
if (widget.playlist?.isImported == true) ...[
  SwitchListTile(
    title: Text(t.library.editPlaylist.useAuthForRefresh),
    subtitle: Text(t.library.editPlaylist.useAuthForRefreshHint),
    value: _useAuthForRefresh,
    onChanged: (v) => setState(() => _useAuthForRefresh = v),
  ),
]
```

### 7.6 帳號管理頁面導入

`AccountPlaylistsSheet` 中的批量導入永遠使用登入狀態：
```dart
await importService.importFromUrl(url, useAuth: true);
```

### 7.7 外部歌單導入（網易雲/QQ/Spotify → 搜索匹配）

**當 URL 被識別為網易雲音樂歌單時的行為變更**：

由於網易雲現在是直接音源，網易雲歌單 URL 應走**內部導入流程**（直接導入），而非外部導入流程（搜索匹配）。

`ImportPlaylistDialog._onUrlChanged()` 中的 URL 類型偵測邏輯調整：
```dart
// 網易雲 URL 現在是內部來源
// 原: 偵測為 external → 搜索匹配
// 新: 偵測為 internal → 直接導入
```

---

## 8. 播放功能重構

### 8.1 帳號管理卡片：登入播放開關

> **實現變更**：原設計為獨立設定頁面，已改為在帳號管理頁面的每個平台卡片上放置開關按鈕。

**文件**: `lib/ui/pages/settings/account_management_page.dart`

每個平台卡片（Bilibili / YouTube / 網易雲）新增「登入播放」按鈕：
- 啟用時：`FilledButton.tonal`（高亮填色）
- 停用時：`OutlinedButton`（中空描邊）
- 僅在已登入時顯示

默認值：Bilibili 關閉、YouTube 關閉、網易雲開啟

### 8.2 QueueManager.ensureAudioStream 改造

```dart
Future<(Track, String?, AudioStreamResult?)> ensureAudioStream(
  Track track, {
  int retryCount = 0,
  bool persist = true,
}) async {
  // ... 本地文件檢查 (不變) ...

  // 決定 auth headers (新邏輯)
  Map<String, String>? authHeaders;
  final settings = await _getSettings();
  final useAuth = settings.useAuthForPlay(track.sourceType);

  if (useAuth) {
    authHeaders = await _getAuthHeaders(track.sourceType);
    // 網易雲未登入時阻止播放
    if (authHeaders == null && track.sourceType == SourceType.netease) {
      throw NeteaseApiException(
        numericCode: 301,
        message: '請先登入網易雲音樂帳號',
      );
    }
  }

  // 獲取音頻流 (傳入 authHeaders)
  final streamResult = await source.getAudioStream(
    track.sourceId,
    config: config,
    authHeaders: authHeaders,
  );
  // ...
}
```

### 8.3 DownloadService 適配

下載時同樣根據 `settings.useAuthForPlay(sourceType)` 決定是否帶 auth headers。

### 8.4 移除 auth 重試

`ImportService` 和 `QueueManager` 中所有 `withAuthRetry` / `withAuthRetryDirect` 呼叫替換為直接的 auth headers 判斷。

---

## 9. 歌詞系統適配

### 9.1 `LyricsAutoMatchService.tryAutoMatch()` 變更

新增直接獲取邏輯（在 `originalSongId` 檢查之前）：

```dart
Future<LyricsResult?> tryAutoMatch(Track track) async {
  // 1. 檢查已有匹配 (不變)
  // ...

  // 2. ★ 新增：網易雲音樂歌曲直接用 sourceId 獲取歌詞
  if (track.sourceType == SourceType.netease) {
    try {
      final result = await _neteaseSource.getLyricsResult(track.sourceId);
      if (result != null) {
        await _saveLyricsMatch(track, result, 'netease');
        return result;
      }
    } catch (_) {
      // 降級到搜索匹配
    }
  }

  // 3. 原平台 ID 直接獲取 (originalSongId，保持不變)
  // 4. 網易雲搜索
  // 5. QQ音樂搜索
  // 6. lrclib fallback
}
```

### 9.2 Phase 2 後

- `sourceType == qqmusic` 的歌曲同樣直接用 `sourceId` 獲取
- 移除 `originalSongId` / `originalSource` 相關邏輯
- `LyricsAutoMatchService` 中的 `_tryDirectFetch()` 簡化為只檢查 `sourceType`

---

## 10. 歌單封面重構

### 10.1 規則

| 條件 | 封面來源 |
|------|---------|
| `hasCustomCover == true` | `coverUrl`（用戶自定義，不自動更新） |
| 導入歌單（有 `sourceUrl`） | `PlaylistParseResult.coverUrl`（平台封面） |
| 刷新時 | 從新的 `PlaylistParseResult.coverUrl` 更新 |
| 手動創建的歌單（無 `sourceUrl`） | 第一首歌的 `thumbnailUrl`（保持現有行為） |

### 10.2 ImportService 變更

導入時：
```dart
// 舊邏輯：使用第一首歌封面
// if (!playlist.hasCustomCover && playlist.trackIds.isNotEmpty) {
//   final firstTrack = await _trackRepository.getById(playlist.trackIds.first);
//   playlist.coverUrl = firstTrack?.thumbnailUrl;
// }

// 新邏輯：使用平台封面
if (!playlist.hasCustomCover && result.coverUrl != null) {
  playlist.coverUrl = result.coverUrl;
}
```

刷新時：
```dart
// 只在刷新時更新封面
if (!playlist.hasCustomCover && result.coverUrl != null) {
  playlist.coverUrl = result.coverUrl;
}
```

### 10.3 BilibiliSource / YouTubeSource parsePlaylist

確保 `PlaylistParseResult.coverUrl` 返回平台封面（目前 Bilibili 的收藏夾 API 已返回 `cover` 字段，YouTube 同理）。需要驗證現有實現是否已正確填充。

---

## 11. UI 變更

### 11.1 TrackTile — VIP 標記

在標題右側添加 VIP 標記（僅 `track.isVip == true` 時顯示）：

```dart
// track_tile.dart 的標題 Row
Row(
  children: [
    Expanded(child: Text(track.title, ...)),
    if (track.isVip)
      Container(
        margin: EdgeInsets.only(left: 4),
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: Colors.amber.withOpacity(0.15),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: Colors.amber.withOpacity(0.5), width: 0.5),
        ),
        child: Text('VIP',
          style: TextStyle(fontSize: 9, color: Colors.amber[700], fontWeight: FontWeight.w600),
        ),
      ),
  ],
)
```

### 11.2 PlaylistDetailPage — Owner 顯示

在歌單描述下方添加所有者信息：

```dart
if (playlist.ownerName != null)
  Text(
    '${t.playlist.owner}: ${playlist.ownerName}',
    style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline),
  ),
```

遠端移除按鈕顯示條件：
```dart
// 只在歌單所有者與當前登入用戶一致時顯示
final currentAccount = ref.watch(accountProvider(playlist.importSourceType));
final showRemoteActions = playlist.ownerUserId != null &&
    currentAccount?.userId == playlist.ownerUserId;
```

### 11.3 搜索頁面 — 新增網易雲 Tab

在搜索來源選擇中新增網易雲選項：

```dart
// 現有: [全部] [Bilibili] [YouTube]
// 新增: [全部] [Bilibili] [YouTube] [網易雲]
```

### 11.4 帳號管理頁面

新增網易雲帳號卡片，與 Bilibili / YouTube 並列：

```dart
_PlatformCard(
  icon: SimpleIcons.neteasecloudmusic,
  title: t.account.netease,
  color: neteaseRed,  // #E60026
  account: neteaseAccount,
  onLogin: () => context.push(RoutePaths.neteaseLogin),
  onLogout: () => _confirmLogout(SourceType.netease),
  onManagePlaylists: () => _showNeteasePlaylistsSheet(),
)
```

### 11.5 設定頁面

在播放設定 section 新增入口：
```dart
ListTile(
  leading: Icon(Icons.vpn_key),
  title: Text(t.settings.authPlayback.title),
  subtitle: Text(t.settings.authPlayback.subtitle),
  trailing: Icon(Icons.chevron_right),
  onTap: () => context.push(RoutePaths.authPlaybackSettings),
),
```

---

## 12. 依賴包

| Package | 版本 | 用途 | 狀態 |
|---------|------|------|------|
| `encrypt` | ^5.0.3 | AES-CBC / AES-ECB 加密 | **需新增** |
| `crypto` | ^3.0.3 | MD5 | 已有 |
| `qr_flutter` | ^4.1.0 | QR 碼顯示 | 已有 |
| `flutter_secure_storage` | ^9.2.4 | Cookie 安全存儲 | 已有 |
| `flutter_inappwebview` | ^6.1.5 | WebView 登入 | 已有 |
| `dio` | ^5.8.0 | HTTP 客戶端 | 已有 |
| `isar` | ^3.1.0 | 數據庫 | 已有 |

---

## 13. 文件清單

### 13.1 新增文件

| 文件 | 說明 |
|------|------|
| `lib/core/utils/netease_crypto.dart` | weapi / eapi 加密工具 |
| `lib/data/sources/netease_source.dart` | NeteaseSource (BaseSource) |
| `lib/data/sources/netease_exception.dart` | NeteaseApiException |
| `lib/services/account/netease_account_service.dart` | 帳號服務 |
| `lib/services/account/netease_credentials.dart` | 憑證模型 |
| `lib/services/account/netease_auth_interceptor.dart` | Dio 攔截器 |
| `lib/ui/pages/settings/netease_login_page.dart` | 登入頁面 |

### 13.2 修改文件

| 文件 | 變更 |
|------|------|
| `lib/data/models/track.dart` | SourceType.netease + isVip 字段 |
| `lib/data/models/playlist.dart` | ownerName, ownerUserId, useAuthForRefresh |
| `lib/data/models/settings.dart` | useXxxAuthForPlay 字段 + 便捷方法 |
| `lib/data/sources/base_source.dart` | PlaylistParseResult 加 ownerName/ownerUserId |
| `lib/data/sources/source_provider.dart` | 註冊 NeteaseSource + Provider |
| `lib/providers/account_provider.dart` | 新增 netease 相關 Provider |
| `lib/providers/database_provider.dart` | _migrateDatabase 新增遷移邏輯 |
| `lib/services/import/import_service.dart` | useAuth 參數 + 封面邏輯 + 所有者保存 |
| `lib/services/audio/queue_manager.dart` | auth headers 由設定控制 |
| `lib/services/lyrics/lyrics_auto_match_service.dart` | 網易雲直接歌詞獲取 |
| `lib/services/download/download_service.dart` | auth headers 由設定控制 |
| `lib/ui/pages/library/widgets/import_playlist_dialog.dart` | 使用登入狀態開關 |
| `lib/ui/pages/library/widgets/create_playlist_dialog.dart` | useAuthForRefresh 開關 |
| `lib/ui/pages/library/playlist_detail_page.dart` | owner 顯示 + 遠端操作條件 |
| `lib/ui/widgets/track_tile.dart` | VIP 標記 |
| `lib/ui/pages/settings/settings_page.dart` | 登入狀態管理入口 |
| `lib/ui/pages/settings/account_management_page.dart` | 新增網易雲卡片 |
| `lib/core/utils/auth_retry_utils.dart` | 重命名 + 移除重試邏輯 + 擴展 netease |
| `lib/core/utils/thumbnail_url_utils.dart` | 新增網易雲圖片 URL 優化 |
| `pubspec.yaml` | 新增 encrypt 依賴 |

### 13.3 刪除項目

| 項目 | 說明 |
|------|------|
| `withAuthRetry()` / `withAuthRetryDirect()` | 在 auth_retry_utils.dart 中刪除 |
| `ImportService` 中的所有 `withAuthRetryDirect` 調用 | 替換為直接 auth headers |
| `QueueManager` 中的 auth 重試邏輯 | 替換為設定控制 |

---

## 14. 實施階段

### Phase 1a — 基礎設施（模型 + 加密）

| 任務 | 文件 | 依賴 |
|------|------|------|
| SourceType 擴展 | track.dart | — |
| Track.isVip 字段 | track.dart | — |
| Playlist 新字段 | playlist.dart | — |
| Settings 新字段 | settings.dart | — |
| PlaylistParseResult 擴展 | base_source.dart | — |
| DB 遷移邏輯 | database_provider.dart | 上述模型變更 |
| build_runner 代碼生成 | *.g.dart | 上述模型變更 |
| NeteaseCrypto 工具 | netease_crypto.dart | encrypt 包 |
| 新增 encrypt 依賴 | pubspec.yaml | — |

### Phase 1b — 帳號系統

| 任務 | 文件 | 依賴 |
|------|------|------|
| NeteaseCredentials | netease_credentials.dart | — |
| NeteaseAccountService | netease_account_service.dart | 1a |
| NeteaseAuthInterceptor | netease_auth_interceptor.dart | NeteaseAccountService |
| Account Providers | account_provider.dart | NeteaseAccountService |
| 登入頁面 | netease_login_page.dart | NeteaseAccountService |
| 帳號管理頁面更新 | account_management_page.dart | Providers |

### Phase 1c — 音源核心

| 任務 | 文件 | 依賴 |
|------|------|------|
| NeteaseApiException | netease_exception.dart | 1a |
| NeteaseSource | netease_source.dart | 1a, NeteaseCrypto |
| SourceManager 註冊 | source_provider.dart | NeteaseSource |
| 搜索頁面更新 | search 相關 | SourceManager |

### Phase 1d — 導入重構

| 任務 | 文件 | 依賴 |
|------|------|------|
| auth_retry_utils 重構 | auth_retry_utils.dart | 1b |
| ImportService useAuth | import_service.dart | 1c, auth_utils |
| ImportPlaylistDialog 改造 | import_playlist_dialog.dart | ImportService |
| 編輯歌單對話框 | create_playlist_dialog.dart | Playlist 模型 |
| 帳號管理頁面導入 | account_playlists_sheet | ImportService |
| 封面邏輯 | import_service.dart | — |

### Phase 1e — 播放重構

| 任務 | 文件 | 依賴 |
|------|------|------|
| 帳號卡片登入播放開關 | account_management_page.dart | Settings 模型 |
| QueueManager 改造 | queue_manager.dart | 1b, 1c, Settings |
| DownloadService 適配 | download_service.dart | 1b, Settings |

### Phase 1f — 歌詞 + UI

| 任務 | 文件 | 依賴 |
|------|------|------|
| 歌詞直接獲取 | lyrics_auto_match_service.dart | 1c |
| VIP 標記 | track_tile.dart | Track.isVip |
| Owner 顯示 | playlist_detail_page.dart | Playlist 新字段 |
| 縮略圖優化 | thumbnail_url_utils.dart | — |

### Phase 1g — i18n

所有新增文字需要添加到 `lib/i18n/` 的 JSON 文件中。

---

## 15. 數據庫遷移

### 15.1 `_migrateDatabase()` 新增邏輯

```dart
// ===== Settings 升級 =====

// 網易雲播放認證默認開啟
// (新字段 bool 默認 false，但我們需要 netease 默認 true)
// 注意：useBilibiliAuthForPlay 和 useYoutubeAuthForPlay 默認 false 不需要遷移
if (!settings.useNeteaseAuthForPlay) {
  // 新安裝時 useNeteaseAuthForPlay = false（Isar 默認值）
  // 但我們希望默認 true，所以需要判斷是否為首次遷移
  // 使用 enabledSources 包含 'netease' 作為已遷移標記
  if (!settings.enabledSources.contains('netease')) {
    settings.useNeteaseAuthForPlay = true;
    settings.enabledSources = [...settings.enabledSources, 'netease'];
    needsUpdate = true;
  }
}

// 網易雲流優先級
if (settings.neteaseStreamPriority.isEmpty) {
  settings.neteaseStreamPriority = 'audioOnly';
  needsUpdate = true;
}

// ===== Playlist 升級 =====
// useAuthForRefresh 默認 false — 符合需求，無需遷移
// ownerName / ownerUserId 默認 null — 符合需求，無需遷移
```

### 15.2 Track.isVip 遷移

Isar `bool` 默認 `false`，符合預期（舊歌曲都不標記為 VIP）。無需額外遷移。

### 15.3 SourceType 枚舉變更

Isar 使用 `@Enumerated(EnumType.name)` 存儲枚舉，新增 `netease` 不影響現有數據。但需要確保 build_runner 重新生成代碼。

---

> **附錄：Phase 2 概要**
>
> Phase 2 (QQ音樂) 按相同模式實現：
> - `SourceType.qqmusic`
> - `QQMusicSource extends BaseSource`
> - `QQMusicAccountService`
> - `QQMusicApiException`
> - 加密層不同（QQ 音樂用不同的加密方案）
>
> Phase 2 完成後：
> - 移除 `Track.originalSongId` 和 `Track.originalSource`
> - `LyricsAutoMatchService` 中 `_tryDirectFetch()` 簡化為只檢查 `sourceType`
> - DB 遷移：清理 `originalSongId` / `originalSource` 字段
