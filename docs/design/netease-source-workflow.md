# 網易雲音樂直接音源集成 — 實施工作流

> **關聯設計文檔**: `docs/design/netease-source-integration.md`
> **日期**: 2026-03-26
> **估算任務數**: 42 個離散任務，分 7 個階段

---

## 階段總覽

| 階段 | 名稱 | 任務數 | 核心目標 |
|------|------|--------|---------|
| 1a | 基礎設施 | 8 | 模型 + 加密 + 依賴 + 代碼生成 |
| 1b | 帳號系統 | 6 | 登入 + Cookie + Provider |
| 1c | 音源核心 | 5 | NeteaseSource + 搜索 |
| 1d | 導入重構 | 7 | auth 重構 + 封面 + 所有者 |
| 1e | 播放重構 | 5 | 設定 + QueueManager + 下載 |
| 1f | 歌詞 + UI | 6 | 歌詞 + VIP + Owner + 縮略圖 |
| 1g | i18n + 收尾 | 5 | 翻譯 + 路由 + 驗證 |

---

## 階段 1a — 基礎設施（模型 + 加密 + 依賴）

### 任務 1a-1：新增 `encrypt` 依賴

**文件**: `pubspec.yaml`

**操作**:
在 `dependencies` 的 `# 加密` section 中，`crypto` 下方新增：
```yaml
  encrypt: ^5.0.3
```

**驗證**: `flutter pub get` 成功

---

### 任務 1a-2：擴展 SourceType 枚舉

**文件**: `lib/data/models/track.dart`

**操作**:
1. 在 `SourceType` 枚舉中 `youtube` 後新增 `netease`
2. 在 `displayName` getter 中新增 `case SourceType.netease: return t.importPlatform.netease;`

**注意**: `@Enumerated(EnumType.name)` 存儲枚舉名稱字串，新增值不影響現有數據

---

### 任務 1a-3：Track 模型新增 isVip 字段

**文件**: `lib/data/models/track.dart`

**操作**:
在 `isAvailable` 字段後（約 line 81）新增：
```dart
/// 是否為 VIP 歌曲（需要付費才能播放）
bool isVip = false;
```

**遷移**: Isar `bool` 默認 `false`，無需遷移邏輯

---

### 任務 1a-4：Playlist 模型新增字段

**文件**: `lib/data/models/playlist.dart`

**操作**:
在 `notifyOnUpdate` 字段後（約 line 39）新增：
```dart
/// 歌單所有者暱稱
String? ownerName;

/// 歌單所有者平台用戶 ID
String? ownerUserId;

/// 刷新時是否使用登入狀態
bool useAuthForRefresh = false;
```

**遷移**: `String?` 默認 `null`，`bool` 默認 `false`，均符合預期

---

### 任務 1a-5：Settings 模型新增字段

**文件**: `lib/data/models/settings.dart`

**操作**:

1. 在音頻質量設置 section（`bilibiliStreamPriority` 後方）新增：
```dart
/// 網易雲流優先級 (逗號分隔)
String neteaseStreamPriority = 'audioOnly';
```

2. 在新 section（所有音頻設置之後）新增：
```dart
// ========== 播放認證設置 ==========

/// Bilibili 播放時使用登入狀態
bool useBilibiliAuthForPlay = false;

/// YouTube 播放時使用登入狀態
bool useYoutubeAuthForPlay = false;

/// 網易雲播放時使用登入狀態
bool useNeteaseAuthForPlay = true;
```

3. 新增 `@ignore` 便捷方法（在現有 `@ignore` getters 區域）：
```dart
/// 獲取指定音源的播放認證設定
@ignore
bool useAuthForPlay(SourceType sourceType) {
  switch (sourceType) {
    case SourceType.bilibili: return useBilibiliAuthForPlay;
    case SourceType.youtube: return useYoutubeAuthForPlay;
    case SourceType.netease: return useNeteaseAuthForPlay;
  }
}

/// 設置指定音源的播放認證設定
set useAuthForPlayBySource((SourceType, bool) pair) {
  switch (pair.$1) {
    case SourceType.bilibili: useBilibiliAuthForPlay = pair.$2;
    case SourceType.youtube: useYoutubeAuthForPlay = pair.$2;
    case SourceType.netease: useNeteaseAuthForPlay = pair.$2;
  }
}

/// 網易雲流優先級列表
@ignore
List<StreamType> get neteaseStreamPriorityList {
  if (neteaseStreamPriority.isEmpty) return [StreamType.audioOnly];
  return neteaseStreamPriority.split(',')
      .map((s) => StreamType.values.firstWhere(
            (t) => t.name == s.trim(),
            orElse: () => StreamType.audioOnly,
          ))
      .toList();
}
```

---

### 任務 1a-6：PlaylistParseResult 擴展

**文件**: `lib/data/sources/base_source.dart`

**操作**:
在 `PlaylistParseResult` 類中新增兩個字段：
```dart
final String? ownerName;
final String? ownerUserId;
```

在 constructor 中新增對應的可選參數：
```dart
this.ownerName,
this.ownerUserId,
```

**影響**: BilibiliSource 和 YouTubeSource 的 `parsePlaylist` 返回值需要補充這兩個字段（可以先傳 null，後續優化）

---

### 任務 1a-7：數據庫遷移邏輯

**文件**: `lib/providers/database_provider.dart`

**操作**:
在 `_migrateDatabase()` 函數的 Settings 升級 section 末尾新增：

```dart
// 網易雲播放認證：新字段 bool 默認 false，但需要默認 true
// 使用 enabledSources 是否包含 'netease' 判斷是否已遷移
if (!settings.enabledSources.contains('netease')) {
  settings.useNeteaseAuthForPlay = true;
  settings.enabledSources = [...settings.enabledSources, 'netease'];
  needsUpdate = true;
}

// 網易雲流優先級
if (settings.neteaseStreamPriority.isEmpty) {
  settings.neteaseStreamPriority = 'audioOnly';
  needsUpdate = true;
}
```

---

### 任務 1a-8：NeteaseCrypto 加密工具

**文件**: `lib/core/utils/netease_crypto.dart` (新建)

**操作**: 實現完整的加密工具類

```dart
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart';
import 'package:crypto/crypto.dart';

class NeteaseCrypto {
  NeteaseCrypto._();

  // ===== 常量 =====
  static const _presetKey = '0CoJUm6Qyw8W8jud';
  static const _iv = '0102030405060708';
  static const _eapiKey = 'e82ckenh8dichen8';
  static const _base62 =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  static const _rsaModulusHex =
      '00e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7b725'
      '152b3ab17a876aea8a5aa76d2e417629ec4ee341f56135fccf695280104e0312'
      'ecbda92557c93870114af6c9d05c4f7f0c3685b7a46bee255932575cce10b424'
      'd813cfe4875d3e82047b97ddef52741d546b8e289dc6935b3ece0462db0a22b8e7';
  static final _rsaModulus = BigInt.parse(_rsaModulusHex, radix: 16);
  static final _rsaExponent = BigInt.from(65537);

  // ===== weapi 加密 =====
  /// 返回 {params, encSecKey} 用於 POST body
  static Map<String, String> weapi(Map<String, dynamic> data) {
    final text = jsonEncode(data);
    final secretKey = _generateRandomKey(16);

    // Layer 1: AES with preset key
    final layer1 = _aesEncrypt(text, _presetKey, _iv);
    // Layer 2: AES with random key
    final params = _aesEncrypt(layer1, secretKey, _iv);
    // RSA: encrypt reversed random key
    final encSecKey = _rsaEncrypt(secretKey);

    return {'params': params, 'encSecKey': encSecKey};
  }

  // ===== eapi 加密 =====
  static String eapi(String url, Map<String, dynamic> data) {
    final text = jsonEncode(data);
    final message = 'nobody${url}use${text}md5forencrypt';
    final digest = md5.convert(utf8.encode(message)).toString();
    final payload = '$url-36cd479b6b5-$text-36cd479b6b5-$digest';

    final encrypter = Encrypter(AES(
      Key.fromUtf8(_eapiKey),
      mode: AESMode.ecb,
      padding: 'PKCS7',
    ));
    final encrypted = encrypter.encryptBytes(utf8.encode(payload));
    return encrypted.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
  }

  // ===== eapi 解密 =====
  static Map<String, dynamic> eapiDecrypt(String hexEncrypted) {
    final bytes = Uint8List.fromList(List.generate(
      hexEncrypted.length ~/ 2,
      (i) => int.parse(hexEncrypted.substring(i * 2, i * 2 + 2), radix: 16),
    ));
    final encrypter = Encrypter(AES(
      Key.fromUtf8(_eapiKey),
      mode: AESMode.ecb,
      padding: 'PKCS7',
    ));
    final decrypted = encrypter.decryptBytes(Encrypted(bytes));
    return jsonDecode(utf8.decode(decrypted));
  }

  // ===== 內部方法 =====
  static String _aesEncrypt(String text, String key, String iv) {
    final encrypter = Encrypter(AES(
      Key.fromUtf8(key),
      mode: AESMode.cbc,
      padding: 'PKCS7',
    ));
    return encrypter.encrypt(text, iv: IV.fromUtf8(iv)).base64;
  }

  static String _generateRandomKey(int length) {
    final random = Random.secure();
    return List.generate(length, (_) => _base62[random.nextInt(_base62.length)])
        .join();
  }

  static String _rsaEncrypt(String text) {
    // Reverse the text
    final reversed = text.split('').reversed.join();
    // Convert to BigInt
    final bytes = utf8.encode(reversed);
    final input = BigInt.parse(
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      radix: 16,
    );
    // RSA: input ^ e mod n (no padding)
    final output = input.modPow(_rsaExponent, _rsaModulus);
    return output.toRadixString(16).padLeft(256, '0');
  }
}
```

**驗證**: 寫一個簡單的測試用已知的輸入/輸出驗證加密正確性

---

### 階段 1a 完成後

運行代碼生成：
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

驗證 `flutter analyze` 通過（允許未使用的新字段警告）。

---

## 階段 1b — 帳號系統

### 任務 1b-1：NeteaseCredentials 憑證模型

**文件**: `lib/services/account/netease_credentials.dart` (新建)

**參考**: `lib/services/account/bilibili_credentials.dart`

**內容**:
```dart
class NeteaseCredentials {
  final String musicU;
  final String csrf;
  final String? userId;
  final DateTime savedAt;

  NeteaseCredentials({
    required this.musicU,
    required this.csrf,
    this.userId,
    required this.savedAt,
  });

  factory NeteaseCredentials.fromJson(Map<String, dynamic> json) =>
    NeteaseCredentials(
      musicU: json['musicU'] as String? ?? '',
      csrf: json['csrf'] as String? ?? '',
      userId: json['userId'] as String?,
      savedAt: json['savedAt'] != null
          ? DateTime.parse(json['savedAt'] as String)
          : DateTime.now(),
    );

  Map<String, dynamic> toJson() => {
    'musicU': musicU,
    'csrf': csrf,
    'userId': userId,
    'savedAt': savedAt.toIso8601String(),
  };

  String toCookieString() => 'MUSIC_U=$musicU; __csrf=$csrf';
}
```

---

### 任務 1b-2：NeteaseAccountService

**文件**: `lib/services/account/netease_account_service.dart` (新建)

**參考**: `lib/services/account/bilibili_account_service.dart` 的結構

**實現要點**:
1. 繼承 `AccountService`，`platform => SourceType.netease`
2. `_storageKey = 'account_netease_credentials'`
3. Dio 默認 headers: `Referer: https://music.163.com`, `Origin: https://music.163.com`
4. `loginWithCookies({musicU, csrf})` — 保存到 SecureStorage + 更新 Account (Isar)
5. `generateQrCode()` — POST `/weapi/login/qrcode/unikey` (用 `NeteaseCrypto.weapi({type: 1})`)
   - 返回 `QrCodeData(url: 'https://music.163.com/login?codekey=$unikey', qrcodeKey: unikey)`
6. `pollQrCodeStatus(qrcodeKey)` — Stream，每 3 秒輪詢
   - POST `/weapi/login/qrcode/client/login` Body: `{type: 1, key: qrcodeKey}`
   - 800→expired, 801→waiting, 802→scanned, 803→success (提取 Set-Cookie)
7. `getAuthCookieString()` — 從 SecureStorage 讀取，返回 `MUSIC_U=xxx; __csrf=xxx`
8. `getAuthHeaders()` — `{'Cookie': cookies}`
9. `getCsrfToken()` — 從 cached credentials 讀取 csrf
10. `checkLoginStatus()` — POST `/weapi/w/nuser/account/get`
11. `logout()` — 清除 SecureStorage + 更新 Account `isLoggedIn = false`
12. `getUserPlaylists()` — POST `/weapi/user/playlist` Body: `{uid: userId, limit: 50, offset: 0}`
13. `refreshCredentials()` → `return true` (MUSIC_U 有效期長)
14. `needsRefresh()` → `return false`
15. `fetchAndUpdateUserInfo()` — 登入後調用 `checkLoginStatus()` 獲取暱稱/頭像，更新 Account

---

### 任務 1b-3：NeteaseAuthInterceptor

**文件**: `lib/services/account/netease_auth_interceptor.dart` (新建)

**參考**: `lib/services/account/bilibili_auth_interceptor.dart`

**實現**:
Dio Interceptor，在 `onRequest` 中自動注入 Cookie header（如果 NeteaseAccountService 已登入）。

比 Bilibili 簡單 — 不需要自動刷新邏輯（MUSIC_U 有效期很長）。

---

### 任務 1b-4：Account Provider 新增網易雲

**文件**: `lib/providers/account_provider.dart`

**操作**:
1. 新增 `neteaseAccountServiceProvider`:
```dart
final neteaseAccountServiceProvider = Provider<NeteaseAccountService>((ref) {
  final isar = ref.watch(isarInstanceProvider);
  return NeteaseAccountService(isar: isar);
});
```

2. 新增 `neteaseAccountProvider`:
```dart
final neteaseAccountProvider = StateNotifierProvider<AccountNotifier, Account?>((ref) {
  final isar = ref.watch(isarInstanceProvider);
  return AccountNotifier(isar: isar, platform: SourceType.netease);
});
```

3. 新增便捷 Provider:
```dart
final isNeteaseLoggedInProvider = Provider<bool>((ref) {
  return ref.watch(neteaseAccountProvider)?.isLoggedIn ?? false;
});
```

4. 更新 `isLoggedInProvider` family（如果有）支持 `SourceType.netease`

---

### 任務 1b-5：網易雲登入頁面

**文件**: `lib/ui/pages/settings/netease_login_page.dart` (新建)

**參考**: `lib/ui/pages/settings/bilibili_login_page.dart`

**結構**:
```dart
class NeteaseLoginPage extends ConsumerStatefulWidget { ... }

class _NeteaseLoginPageState extends ConsumerState<NeteaseLoginPage>
    with SingleTickerProviderStateMixin {
  // Android: TabBar (WebView + QR Code)
  // Desktop: 僅顯示 QR Code（無 TabBar）
}

class _NeteaseWebViewLoginTab extends ConsumerStatefulWidget {
  // 載入 https://music.163.com/#/login
  // 監控 Cookie 變化，檢測 MUSIC_U 出現
  // 成功後調用 accountService.loginWithCookies()
}

class _NeteaseQrCodeLoginTab extends ConsumerStatefulWidget {
  // 使用 accountService.generateQrCode()
  // 顯示 QrImageView
  // 監聽 accountService.pollQrCodeStatus() Stream
  // 顯示狀態文字（等待掃碼 / 已掃碼 / 已過期）
  // 成功後 Toast + Navigator.pop()
}
```

**平台判斷**: `Platform.isAndroid` → 顯示 TabBar，否則僅 QR Code

---

### 任務 1b-6：帳號管理頁面新增網易雲卡片

**文件**: `lib/ui/pages/settings/account_management_page.dart`

**操作**:
在現有 Bilibili / YouTube 卡片之後新增網易雲卡片：
```dart
// 網易雲帳號卡片
final neteaseAccount = ref.watch(neteaseAccountProvider);
_PlatformCard(
  icon: SimpleIcons.neteasecloudmusic,
  title: t.account.netease,
  color: const Color(0xFFE60026),  // 網易雲紅
  account: neteaseAccount,
  onLogin: () => context.push(RoutePaths.neteaseLogin),
  onLogout: () => _confirmLogout(SourceType.netease),
  onManagePlaylists: () => _showNeteasePlaylistsSheet(context),
),
```

新增 `_showNeteasePlaylistsSheet` 方法 — 參考 Bilibili 的 `_showBilibiliPlaylistsSheet`，但使用 `NeteaseAccountService.getUserPlaylists()`。

---

## 階段 1c — 音源核心

### 任務 1c-1：NeteaseApiException

**文件**: `lib/data/sources/netease_exception.dart` (新建)

按設計文檔 §5.1 實現。繼承 `SourceApiException`，numericCode 映射語義碼。

---

### 任務 1c-2：NeteaseSource — BaseSource 實現

**文件**: `lib/data/sources/netease_source.dart` (新建)

**這是最核心的文件**。按設計文檔 §4 實現所有 BaseSource 方法。

**關鍵實現細節**:

1. **Dio 實例**: 帶 `Referer`, `Origin`, `User-Agent` headers
2. **所有 API 請求使用 `NeteaseCrypto.weapi()` 加密**
3. **parseId()**: 匹配 `music.163.com/song?id=\d+` 和 `music.163.com/#/song?id=\d+`
4. **isPlaylistUrl()**: 匹配 `music.163.com/playlist?id=\d+` 和短鏈 `163cn.tv`
5. **getTrackInfo()**: POST `/weapi/v3/song/detail`
   - 需要同時請求 privilege 信息
   - 判斷 VIP: `fee == 1 || fee == 4` → `track.isVip = true`
   - 判斷可用: `st == -200` → `track.isAvailable = false`
6. **getAudioStream()**: POST `/weapi/song/enhance/player/url/v1`
   - 需要帶 `csrf_token` 參數（從 authHeaders Cookie 中提取）
   - level 映射: high→exhigh, medium→higher, low→standard
   - url 為 null 時拋出 `NeteaseApiException`
   - 過期時間: `DateTime.now().add(Duration(seconds: (expi * 0.8).toInt()))`
7. **search()**: POST `/weapi/cloudsearch/get/web`
   - type: 1 (歌曲)
   - 返回的 Track 需設置 isVip
8. **parsePlaylist()**: 兩步驟
   - Step 1: POST `/weapi/v3/playlist/detail` — 獲取元數據 + trackIds
   - Step 2: 分批（每 400 個）POST `/weapi/v3/song/detail` — 獲取歌曲詳情 + privilege
   - 返回 `PlaylistParseResult` 帶 `ownerName`, `ownerUserId`, `coverUrl`
9. **refreshAudioUrl()**: 調用 getAudioStream()
10. **checkAvailability()**: 調用 getTrackInfo 檢查 isAvailable

**複用**: 可以複用 `lib/data/sources/playlist_import/netease_playlist_source.dart` 中的 URL 解析正則和短鏈解析邏輯。

---

### 任務 1c-3：SourceManager 註冊 NeteaseSource

**文件**: `lib/data/sources/source_provider.dart`

**操作**:
1. 在 `SourceManager` constructor 中新增：
```dart
_sources.add(NeteaseSource());
```

2. 在 `dispose()` 中新增：
```dart
if (source is NeteaseSource) {
  source.dispose();
}
```

3. 新增 Provider：
```dart
final neteaseSourceProvider = Provider<NeteaseSource>((ref) {
  final manager = ref.watch(sourceManagerProvider);
  return manager.getSource(SourceType.netease) as NeteaseSource;
});
```

---

### 任務 1c-4：搜索頁面新增網易雲 Tab

**文件**: 搜索相關文件（`lib/ui/pages/search/search_page.dart` 和 `lib/providers/search_provider.dart`）

**操作**:
1. 在搜索來源 Tab 列表中新增「網易雲」選項
2. 確保 `searchAll()` 或來源篩選邏輯包含 `SourceType.netease`
3. 搜索結果中的 Track 會自動帶有 `isVip` 標記

---

### 任務 1c-5：ImportPlaylistDialog URL 偵測更新

**文件**: `lib/ui/pages/library/widgets/import_playlist_dialog.dart`

**操作**:
更新 `_onUrlChanged()` 中的 URL 偵測邏輯：

網易雲 URL 現在是**內部來源**（直接導入），不再是外部來源（搜索匹配）：

1. 在內部來源檢查（`sourceManager.getSourceForUrl()`）之前，**移除**外部來源對網易雲的匹配
2. `SourceManager.getSourceForUrl()` 現在會返回 `NeteaseSource`（因為 1c-3 已註冊）
3. `_SourcePlatform` 枚舉和 `_getSourceIcon` 中 `netease` 的 case 已有，無需修改

注意：需要確保 `SourceManager` 的 URL 匹配優先級正確（NeteaseSource.canHandle 或 isPlaylistUrl 應在外部來源偵測之前被匹配到）。

---

## 階段 1d — 導入重構

### 任務 1d-1：auth_retry_utils 重構

**文件**: `lib/core/utils/auth_retry_utils.dart`

**操作**:
1. **刪除** `withAuthRetry()` 函數
2. **刪除** `withAuthRetryDirect()` 函數
3. **保留** `buildAuthHeaders()` — 新增 `SourceType.netease` case：
```dart
case SourceType.netease:
  return await neteaseAccountService?.getAuthHeaders();
```
4. **保留** `getAuthHeadersForPlatform()` — 新增 `neteaseAccountService` 參數
5. 可選：重命名文件為 `auth_headers_utils.dart`（需更新所有 import）

---

### 任務 1d-2：ImportService 新增 useAuth 參數

**文件**: `lib/services/import/import_service.dart`

**操作**:

1. Constructor 新增 `NeteaseAccountService?` 參數：
```dart
final NeteaseAccountService? _neteaseAccountService;

ImportService({
  // ... 現有參數 ...
  NeteaseAccountService? neteaseAccountService,
}) : // ... 現有初始化 ...
     _neteaseAccountService = neteaseAccountService;
```

2. `_getAuthHeaders()` 更新：
```dart
Future<Map<String, String>?> _getAuthHeaders(SourceType sourceType) =>
    buildAuthHeaders(sourceType,
        bilibiliAccountService: _bilibiliAccountService,
        youtubeAccountService: _youtubeAccountService,
        neteaseAccountService: _neteaseAccountService);
```

3. `importFromUrl()` 新增 `useAuth` 參數：
```dart
Future<ImportResult> importFromUrl(
  String url, {
  String? customName,
  int? refreshIntervalHours,
  bool notifyOnUpdate = true,
  bool useAuth = false,  // 新增
}) async {
```

4. 替換 `withAuthRetryDirect` 調用：
```dart
// 舊:
// final result = await withAuthRetryDirect(
//   action: (authHeaders) => source.parsePlaylist(url, authHeaders: authHeaders),
//   getAuthHeaders: () => _getAuthHeaders(source.sourceType),
// );

// 新:
Map<String, String>? authHeaders;
if (useAuth) {
  authHeaders = await _getAuthHeaders(source.sourceType);
}
final result = await source.parsePlaylist(url, authHeaders: authHeaders);
```

5. 保存所有者信息：
```dart
playlist.ownerName = result.ownerName;
playlist.ownerUserId = result.ownerUserId;
playlist.useAuthForRefresh = useAuth;
```

6. 封面邏輯更新（替換「使用第一首歌封面」的代碼）：
```dart
// 導入歌單使用平台封面
if (!playlist.hasCustomCover && result.coverUrl != null) {
  playlist.coverUrl = result.coverUrl;
}
// 只有非導入歌單（手動創建）才用第一首歌封面
else if (!playlist.hasCustomCover && !playlist.isImported && playlist.trackIds.isNotEmpty) {
  final firstTrack = await _trackRepository.getById(playlist.trackIds.first);
  if (firstTrack?.thumbnailUrl != null) {
    playlist.coverUrl = firstTrack!.thumbnailUrl;
  }
}
```

---

### 任務 1d-3：refreshPlaylist 重構

**文件**: `lib/services/import/import_service.dart`

**操作**:

1. 替換 `refreshPlaylist()` 中的 `withAuthRetryDirect` 調用：
```dart
// 舊:
// final result = await withAuthRetryDirect(...)

// 新:
Map<String, String>? authHeaders;
if (playlist.useAuthForRefresh) {
  authHeaders = await _getAuthHeaders(source.sourceType);
}
final result = await source.parsePlaylist(playlist.sourceUrl!, authHeaders: authHeaders);
```

2. 刷新封面邏輯：
```dart
// 刷新時更新平台封面（除非自定義）
if (!playlist.hasCustomCover && result.coverUrl != null) {
  playlist.coverUrl = result.coverUrl;
}
```

3. 同樣替換 `_expandMultiPageVideos` 中的 `withAuthRetryDirect` 調用

---

### 任務 1d-4：ImportPlaylistDialog 新增「使用登入狀態」開關

**文件**: `lib/ui/pages/library/widgets/import_playlist_dialog.dart`

**操作**:

1. 新增 state 變量：
```dart
bool _useAuth = false;
```

2. 在 UI 中（歌單名稱輸入框之後、搜索來源選擇之前）新增：
```dart
// 使用登入狀態開關（僅內部來源顯示）
if (_detected?.type == _UrlType.internal && !_isImporting) ...[
  const SizedBox(height: 8),
  SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(t.library.importPlaylist.useAuth),
    subtitle: Text(
      t.library.importPlaylist.useAuthHint,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: colorScheme.outline,
      ),
    ),
    value: _useAuth,
    onChanged: (v) => setState(() => _useAuth = v),
  ),
],
```

3. `_startInternalImport()` 中傳遞 `useAuth`：
```dart
final result = await importService.importFromUrl(
  url,
  customName: customName.isEmpty ? null : customName,
  useAuth: _useAuth,  // 新增
);
```

---

### 任務 1d-5：編輯歌單對話框新增 useAuthForRefresh

**文件**: `lib/ui/pages/library/widgets/create_playlist_dialog.dart`

**操作**:

1. 新增 state 變量（在 `initState` 中從 playlist 讀取）：
```dart
bool _useAuthForRefresh = false;

@override
void initState() {
  super.initState();
  // ... 現有初始化 ...
  _useAuthForRefresh = widget.playlist?.useAuthForRefresh ?? false;
}
```

2. 在自動刷新 section 附近新增（僅已導入歌單顯示）：
```dart
if (widget.playlist?.isImported == true) ...[
  SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(t.library.editPlaylist.useAuthForRefresh),
    subtitle: Text(t.library.editPlaylist.useAuthForRefreshHint),
    value: _useAuthForRefresh,
    onChanged: (v) => setState(() => _useAuthForRefresh = v),
  ),
],
```

3. 提交時保存：
```dart
playlist.useAuthForRefresh = _useAuthForRefresh;
```

---

### 任務 1d-6：帳號管理頁面導入使用登入狀態

**文件**: `lib/ui/pages/settings/widgets/account_playlists_sheet.dart`

**操作**:
在批量導入調用中確保 `useAuth: true`：
```dart
final result = await importService.importFromUrl(
  importUrl,
  customName: null,
  useAuth: true,  // 帳號管理頁面永遠使用登入狀態
);
```

新增網易雲的 AccountPlaylistsSheet 變體（或使其通用化，支持 `SourceType` 參數）。

---

### 任務 1d-7：確認 BilibiliSource / YouTubeSource parsePlaylist 返回平台封面

**文件**: `lib/data/sources/bilibili_source.dart`, `lib/data/sources/youtube_source.dart`

**操作**:
檢查現有 `parsePlaylist()` 是否已正確填充 `PlaylistParseResult.coverUrl`。

- Bilibili 收藏夾 API 返回 `cover` 字段 — 確認已使用
- YouTube 播放列表 — 確認已使用

同時補充 `ownerName` 和 `ownerUserId`：
- Bilibili: `upper.name`, `upper.mid`
- YouTube: channel name, channel ID

---

## 階段 1e — 播放重構

### 任務 1e-1：登入狀態播放設定頁面

**文件**: `lib/ui/pages/settings/auth_playback_settings_page.dart` (新建)

**UI 結構**:
```dart
class AuthPlaybackSettingsPage extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t.settings.authPlayback.title)),
      body: ListView(children: [
        // 說明文字
        Padding(
          padding: EdgeInsets.all(16),
          child: Text(t.settings.authPlayback.description, ...),
        ),
        // 各平台開關
        SwitchListTile(
          title: Text('Bilibili'),
          subtitle: Text(t.settings.authPlayback.defaultOff),
          value: settings.useBilibiliAuthForPlay,
          onChanged: (v) => _updateSetting(ref, SourceType.bilibili, v),
        ),
        SwitchListTile(
          title: Text('YouTube'),
          subtitle: Text(t.settings.authPlayback.defaultOff),
          value: settings.useYoutubeAuthForPlay,
          onChanged: (v) => _updateSetting(ref, SourceType.youtube, v),
        ),
        SwitchListTile(
          title: Text(t.importPlatform.netease),
          subtitle: Text(t.settings.authPlayback.defaultOn),
          value: settings.useNeteaseAuthForPlay,
          onChanged: (v) => _updateSetting(ref, SourceType.netease, v),
        ),
      ]),
    );
  }
}
```

---

### 任務 1e-2：QueueManager auth 邏輯改造

**文件**: `lib/services/audio/queue_manager.dart`

**操作**:

1. Constructor 新增 `NeteaseAccountService` 參數
2. `_getAuthHeaders` 更新支持 netease
3. `ensureAudioStream()` 替換 `withAuthRetryDirect`：

```dart
// 舊:
// final streamResult = await withAuthRetryDirect(
//   action: (authHeaders) => source.getAudioStream(...),
//   getAuthHeaders: () => _getAuthHeaders(track.sourceType),
// );

// 新:
Map<String, String>? authHeaders;
final settings = await _getSettings();
if (settings.useAuthForPlay(track.sourceType)) {
  authHeaders = await _getAuthHeaders(track.sourceType);
  // 網易雲未登入阻止播放
  if (authHeaders == null && track.sourceType == SourceType.netease) {
    throw NeteaseApiException(
      numericCode: 301,
      message: t.error.neteaseLoginRequired,
    );
  }
}
final streamResult = await source.getAudioStream(
  track.sourceId, config: config, authHeaders: authHeaders,
);
```

4. 同樣替換 `ensureAudioUrl()` 和 `getAlternativeAudioStream()` 中的類似邏輯

---

### 任務 1e-3：DownloadService auth 邏輯改造

**文件**: `lib/services/download/download_service.dart`

**操作**:

1. Constructor 新增 `NeteaseAccountService` 參數
2. 替換 `withAuthRetryDirect` 調用（約 line 614）：

```dart
// 舊:
// final streamResult = await withAuthRetryDirect(
//   action: (authHeaders) => source.getAudioStream(track.sourceId, ...),
//   getAuthHeaders: () => _getAuthHeaders(track.sourceType),
// );

// 新:
Map<String, String>? authHeaders;
final settings = await _getSettings();
if (settings.useAuthForPlay(track.sourceType)) {
  authHeaders = await _getAuthHeaders(track.sourceType);
}
final streamResult = await source.getAudioStream(
  track.sourceId, config: config, authHeaders: authHeaders,
);
```

3. 下載網易雲音頻時需要在 HTTP headers 中帶 `Referer: https://music.163.com`

---

### 任務 1e-4：設定頁面新增入口

**文件**: `lib/ui/pages/settings/settings_page.dart`

**操作**:
在「播放設定」section 中新增：
```dart
ListTile(
  leading: const Icon(Icons.vpn_key_outlined),
  title: Text(t.settings.authPlayback.title),
  subtitle: Text(t.settings.authPlayback.subtitle),
  trailing: const Icon(Icons.chevron_right),
  onTap: () => context.push(RoutePaths.authPlaybackSettings),
),
```

---

### 任務 1e-5：路由註冊

**文件**: 路由配置文件（`lib/ui/` 中的路由定義）

**操作**:
1. 新增 `RoutePaths.neteaseLogin` 路由
2. 新增 `RoutePaths.authPlaybackSettings` 路由
3. 分別指向 `NeteaseLoginPage` 和 `AuthPlaybackSettingsPage`

---

## 階段 1f — 歌詞 + UI

### 任務 1f-1：歌詞直接獲取

**文件**: `lib/services/lyrics/lyrics_auto_match_service.dart`

**操作**:
在 `tryAutoMatch()` 方法中，在 `originalSongId` 檢查**之前**插入：

```dart
// 網易雲歌曲直接用 sourceId 獲取歌詞（跳過搜索）
if (track.sourceType == SourceType.netease) {
  try {
    final result = await _neteaseSource.getLyricsResult(track.sourceId);
    if (result != null && result.hasSyncedLyrics) {
      await _saveMatch(track, result, 'netease', track.sourceId);
      logInfo('Auto-matched lyrics via netease sourceId: ${track.sourceId}');
      return true;
    }
  } catch (e) {
    logDebug('Direct lyrics fetch failed for netease ${track.sourceId}: $e');
    // 降級到搜索匹配
  }
}
```

---

### 任務 1f-2：TrackTile VIP 標記

**文件**: `lib/ui/widgets/track_tile.dart`

**操作**:
在標題 `Text` widget 之後（或改為 `Row` 包裝），添加 VIP 標記：

```dart
// 標題行
Row(
  children: [
    Expanded(
      child: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: titleStyle,
      ),
    ),
    if (track.isVip) ...[
      const SizedBox(width: 4),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.5), width: 0.5),
        ),
        child: Text(
          'VIP',
          style: TextStyle(
            fontSize: 9,
            color: Colors.amber[700],
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  ],
)
```

需要在 Standard mode 和 Ranking mode 中都添加。

---

### 任務 1f-3：PlaylistDetailPage Owner 顯示

**文件**: `lib/ui/pages/library/playlist_detail_page.dart`

**操作**:

1. 在歌單描述下方添加所有者信息：
```dart
if (playlist.ownerName != null) ...[
  const SizedBox(height: 4),
  Text(
    '${t.playlist.owner}: ${playlist.ownerName}',
    style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline),
  ),
],
```

2. 遠端移除操作按鈕條件更新：
```dart
// 只在歌單所有者與當前登入用戶一致時顯示遠端操作
final currentAccount = ref.watch(
  playlist.importSourceType != null
    ? accountProviderForType(playlist.importSourceType!)
    : bilibiliAccountProvider,  // fallback
);
final showRemoteActions = playlist.ownerUserId != null &&
    currentAccount?.userId == playlist.ownerUserId;
```

---

### 任務 1f-4：縮略圖 URL 優化

**文件**: `lib/core/utils/thumbnail_url_utils.dart`

**操作**:
新增網易雲圖片 URL 優化方法：

```dart
// 在 getOptimizedUrl() 中新增判斷
if (url.contains('music.126.net') || url.contains('p1.music.126.net') ||
    url.contains('p2.music.126.net')) {
  return _optimizeNeteaseUrl(url, targetWidth);
}

/// 網易雲圖片 URL 優化
/// 原始: http://p1.music.126.net/xxx.jpg
/// 優化: http://p1.music.126.net/xxx.jpg?param=200y200
static String _optimizeNeteaseUrl(String url, int targetWidth) {
  // 網易雲支持 ?param={w}y{h} 參數調整圖片大小
  final size = _getNearestSize(targetWidth, [100, 200, 400, 800]);
  // 移除已有的 param 參數
  final baseUrl = url.split('?').first;
  return '$baseUrl?param=${size}y$size';
}
```

---

### 任務 1f-5：Settings `enabledSources` 更新

**文件**: 搜索相關 Provider

**操作**:
確保 `enabledSources` 設定值正確用於搜索頁面的來源篩選。默認值 `['bilibili', 'youtube']` 遷移後變為 `['bilibili', 'youtube', 'netease']`。

---

### 任務 1f-6：NeteasePlaylistSource 的 URL 去重

**文件**: `lib/ui/pages/library/widgets/import_playlist_dialog.dart`

**操作**:
由於網易雲 URL 現在同時被 NeteaseSource (internal) 和 NeteasePlaylistSource (external) 匹配，需要確保 `_onUrlChanged()` 中 internal 檢查優先於 external 檢查。

當前代碼順序是 external 先於 internal — **需要調整順序**，或者在 external 偵測中排除已被 internal 匹配的 URL。

建議方案：先檢查 internal，如果 internal 匹配了就不再檢查 external。

---

## 階段 1g — i18n + 收尾

### 任務 1g-1：i18n 文字新增

**文件**: `lib/i18n/zh-CN/`, `lib/i18n/zh-TW/`, `lib/i18n/en/` 下的 JSON 文件

**需要新增的 key（示例）**:

```json
// account.i18n.json
"netease": "網易雲音樂",
"neteaseLoginTitle": "登入網易雲音樂",

// importPlatform (在 general 或 track 相關文件中)
"netease": "網易雲音樂",

// library/importPlaylist
"useAuth": "使用登入狀態導入",
"useAuthHint": "對私人歌單或需要登入才能查看的內容，請開啟此選項",

// library/editPlaylist
"useAuthForRefresh": "使用登入狀態刷新",
"useAuthForRefreshHint": "開啟後自動刷新和手動刷新時使用登入帳號的憑證",

// settings/authPlayback
"title": "登入狀態管理",
"subtitle": "設定播放和下載時是否使用登入狀態",
"description": "開啟後，播放和下載歌曲時會使用登入帳號的憑證獲取音頻流",
"defaultOn": "默認開啟",
"defaultOff": "默認關閉",

// playlist
"owner": "所有者",

// error
"neteaseLoginRequired": "請先登入網易雲音樂帳號",
```

**完成後運行**: `dart run slang`

---

### 任務 1g-2：路由完整配置

確認所有新頁面路由已在 GoRouter 配置中註冊：
- `/settings/netease-login` → `NeteaseLoginPage`
- `/settings/auth-playback` → `AuthPlaybackSettingsPage`

---

### 任務 1g-3：移除所有 withAuthRetry 引用

全局搜索 `withAuthRetry` 和 `withAuthRetryDirect`，確認所有調用點都已替換：

- `lib/services/import/import_service.dart` — 已在 1d-2, 1d-3 替換
- `lib/services/audio/queue_manager.dart` — 已在 1e-2 替換
- `lib/services/download/download_service.dart` — 已在 1e-3 替換
- 其他可能的調用點 — 搜索確認

---

### 任務 1g-4：`flutter analyze` 通過

運行 `flutter analyze`，修復所有新增代碼引起的錯誤和警告。

---

### 任務 1g-5：端到端驗證

手動驗證清單：

- [ ] 加密：weapi 加密輸出格式正確（params + encSecKey）
- [ ] QR 碼登入：生成 → 掃碼 → 登入成功 → 帳號信息顯示
- [ ] 搜索：搜索網易雲歌曲，結果正確顯示，VIP 標記可見
- [ ] 播放：點擊搜索結果播放，音頻正常
- [ ] 導入歌單：匿名導入公開歌單成功
- [ ] 導入歌單（登入）：使用登入狀態導入私人歌單成功
- [ ] 歌單封面：顯示平台封面而非第一首歌封面
- [ ] 歌單所有者：在詳情頁顯示
- [ ] 刷新歌單：使用/不使用登入狀態刷新
- [ ] 下載：下載網易雲歌曲成功
- [ ] 歌詞：網易雲歌曲自動匹配歌詞（直接獲取，非搜索）
- [ ] 設定：登入狀態播放設定生效
- [ ] 未登入播放：網易雲歌曲在未登入時 Toast 提示
- [ ] Bilibili/YouTube 不受影響：現有功能正常

---

## 依賴圖

```
1a-1 (encrypt 依賴)
  └→ 1a-8 (NeteaseCrypto)
       └→ 1b-2 (NeteaseAccountService)
       └→ 1c-2 (NeteaseSource)

1a-2~7 (模型變更)
  └→ 代碼生成 (build_runner)
       └→ 所有後續階段

1b-1~6 (帳號系統)
  └→ 1c-2 (NeteaseSource 需要 auth headers)
  └→ 1d-1 (auth_retry 重構需要 netease service)
  └→ 1e-2 (QueueManager 需要 netease service)

1c-1~5 (音源核心)
  └→ 1d-2 (ImportService 需要 NeteaseSource 在 SourceManager 中)
  └→ 1e-2 (QueueManager 需要 NeteaseSource)
  └→ 1f-1 (歌詞需要能識別 netease sourceType)

1d-1~7 (導入重構) — 可與 1e 並行

1e-1~5 (播放重構) — 可與 1d 並行

1f-1~6 (歌詞 + UI) — 依賴 1c + 1d

1g (收尾) — 依賴所有前序階段
```

---

## 風險與緩解

| 風險 | 影響 | 緩解 |
|------|------|------|
| weapi 加密實現不正確 | 所有 API 調用失敗 | 1a-8 完成後立即驗證（用已知輸入測試） |
| 網易雲 API 變更/封鎖 | 功能不可用 | 加密層獨立封裝，便於替換；eapi 作為備選 |
| QR 碼登入 cookie 提取失敗 | 無法登入 | 參考成功實現（linghuaplayer）；備選方案：手動輸入 Cookie |
| VIP 歌曲大量存在 | 用戶體驗差 | TrackTile 明確顯示 VIP 標記；播放失敗 Toast 清晰 |
| 歌單封面變更影響 Bilibili/YouTube | 視覺回歸 | 1d-7 驗證現有平台 coverUrl 填充 |
