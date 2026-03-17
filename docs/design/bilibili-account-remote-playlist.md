# Bilibili 帳號管理 & 遠程歌單操作 — 系統設計文檔

## 1. 概述

為 FMP 添加 Bilibili 帳號登錄能力，並基於登錄態實現遠程收藏夾的添加/移除操作。
設計上預留 YouTube 及其他平台的擴展接口。

### 1.1 核心功能

| 功能 | 說明 |
|------|------|
| 帳號登錄 | WebView 登錄（主要）+ QR 碼登錄（備選） |
| Cookie 管理 | 安全存儲、自動刷新、過期檢測 |
| 添加到遠程收藏夾 | 獲取收藏夾列表 + 已存在標記，勾選後提交 |
| 從遠程收藏夾移除 | 僅導入歌單詳情頁，同時移除本地 |
| 本地歌單刷新 | 遠程操作後自動刷新對應的本地導入歌單 |

### 1.2 新增依賴

```yaml
# WebView（Android + Windows 統一）
flutter_inappwebview: ^6.x    # WebView2 on Windows, WKWebView/Android WebView

# QR 碼生成（備選登錄方式）
qr_flutter: ^4.x

# 安全存儲（Cookie/Token 加密）
flutter_secure_storage: ^9.x

# RSA 加密（Cookie 刷新流程）
pointycastle: ^3.x
```

---

## 2. 數據模型

### 2.1 Account（Isar Collection）

```dart
@collection
class Account {
  Id id = Isar.autoIncrement;

  /// 平台類型
  @Enumerated(EnumType.name)
  late SourceType platform;  // bilibili / youtube

  /// 平台用戶 ID（Bilibili: DedeUserID）
  String? userId;

  /// 用戶暱稱
  String? userName;

  /// 頭像 URL
  String? avatarUrl;

  /// 是否已登錄
  bool isLoggedIn = false;

  /// 上次認證刷新時間
  DateTime? lastRefreshed;

  /// 登錄時間
  DateTime? loginAt;
}
```

**注意：** Cookie/Token 等敏感憑據不存 Isar，存 `flutter_secure_storage`。
Account 模型只存非敏感的用戶信息和狀態。

### 2.2 憑據存儲（flutter_secure_storage）

Key 格式：`account_{platform}_credentials`

```dart
/// Bilibili 憑據結構（JSON 序列化存儲）
class BilibiliCredentials {
  final String sessdata;
  final String biliJct;       // CSRF token
  final String dedeUserId;
  final String dedeUserIdCkMd5;
  final String refreshToken;
  final DateTime savedAt;
}
```

### 2.3 Track 模型擴展

```dart
// Track 新增字段（用於緩存 Bilibili aid，避免每次遠程操作都調 view API）
int? bilibiliAid;  // Bilibili 視頻 aid（收藏夾 API 需要）
```

**遷移邏輯**（`_migrateDatabase()`）：
- `bilibiliAid` 默認 `null`，無需特殊遷移
- 首次使用遠程收藏夾功能時，通過 view API 獲取並緩存

### 2.4 Database Schema 變更

`databaseProvider` 中 `Isar.open()` 的 schemas 列表新增 `AccountSchema`：

```dart
final isar = await Isar.open([
  TrackSchema,
  PlaylistSchema,
  PlayQueueSchema,
  SettingsSchema,
  SearchHistorySchema,
  DownloadTaskSchema,
  PlayHistorySchema,
  RadioStationSchema,
  LyricsMatchSchema,
  AccountSchema,        // 新增
], ...);
```

---

## 3. 服務層架構

### 3.1 文件結構

```
lib/services/account/
├── account_service.dart              # 抽象帳號服務接口
├── bilibili_account_service.dart     # Bilibili 實現
├── bilibili_auth_interceptor.dart    # Dio 攔截器（注入認證 Cookie）
├── bilibili_credentials.dart         # 憑據模型
└── bilibili_favorites_service.dart   # 收藏夾 CRUD 操作

lib/providers/
└── account_provider.dart             # 帳號狀態 Providers

lib/ui/pages/settings/
├── account_management_page.dart      # 帳號管理頁面
└── bilibili_login_page.dart          # Bilibili 登錄頁（WebView + QR）

lib/ui/widgets/dialogs/
└── add_to_remote_playlist_dialog.dart  # 遠程收藏夾彈窗
```

### 3.2 AccountService 抽象接口

```dart
/// 帳號服務抽象接口（可擴展到 YouTube、網易雲等）
abstract class AccountService {
  SourceType get platform;

  /// 檢查是否已登錄
  Future<bool> isLoggedIn();

  /// 獲取當前用戶信息
  Future<Account?> getCurrentAccount();

  /// 登出
  Future<void> logout();

  /// 刷新認證（Cookie/Token）
  /// 返回 true 表示刷新成功，false 表示需要重新登錄
  Future<bool> refreshCredentials();

  /// 檢查認證是否需要刷新
  Future<bool> needsRefresh();
}
```

### 3.3 BilibiliAccountService

```dart
class BilibiliAccountService extends AccountService with Logging {
  final Dio _dio;  // 獨立 Dio 實例（不走 BilibiliSource 的 Dio）
  final FlutterSecureStorage _secureStorage;
  final Isar _isar;

  @override
  SourceType get platform => SourceType.bilibili;

  // ===== 登錄 =====

  /// WebView 登錄完成後，從 WebView 提取的 cookies 初始化
  Future<void> loginWithCookies({
    required String sessdata,
    required String biliJct,
    required String dedeUserId,
    required String dedeUserIdCkMd5,
    required String refreshToken,
  });

  /// QR 碼登錄 - 生成 QR 碼
  Future<QrCodeData> generateQrCode();

  /// QR 碼登錄 - 輪詢掃碼狀態
  /// 返回 Stream，UI 可以監聽狀態變化
  Stream<QrCodePollResult> pollQrCodeStatus(String qrcodeKey);

  // ===== 認證管理 =====

  /// 獲取當前認證 Cookie 字符串（供 Dio 攔截器使用）
  Future<String?> getAuthCookieString();

  /// 獲取 CSRF token（供 POST 請求使用）
  Future<String?> getCsrfToken();

  /// 獲取用戶 mid（供收藏夾 API 使用）
  Future<String?> getUserMid();

  @override
  Future<bool> refreshCredentials();
  // 實現 Web Cookie 刷新流程：
  // 1. GET /x/passport-login/web/cookie/info → 檢查是否需要刷新
  // 2. RSA-OAEP 加密 "refresh_{timestamp}" → correspondPath
  // 3. GET /correspond/1/{correspondPath} → 解析 HTML 獲取 refresh_csrf
  // 4. POST /x/passport-login/web/cookie/refresh → 獲取新 Cookie
  // 5. POST /x/passport-login/web/confirm/refresh → 確認刷新

  // ===== 用戶信息 =====

  /// 獲取用戶信息（頭像、暱稱等）
  /// 調用 GET /x/web-interface/nav
  Future<void> fetchAndUpdateUserInfo();
}
```

### 3.4 BilibiliFavoritesService

```dart
/// Bilibili 收藏夾操作服務
class BilibiliFavoritesService with Logging {
  final BilibiliAccountService _accountService;
  final Dio _dio;  // 使用帶認證攔截器的 Dio

  /// 獲取用戶收藏夾列表（帶視頻已存在標記）
  ///
  /// [videoAid] 如果提供，每個收藏夾的 favState 會標記該視頻是否已存在
  /// 調用 GET /x/v3/fav/folder/created/list-all?up_mid={mid}&rid={aid}&type=2
  Future<List<BilibiliFavFolder>> getFavFolders({int? videoAid});

  /// 添加/移除視頻到收藏夾（原子操作）
  ///
  /// 調用 POST /x/v3/fav/resource/deal
  /// [addFolderIds] 要添加到的收藏夾 mlid 列表
  /// [removeFolderIds] 要從中移除的收藏夾 mlid 列表
  Future<void> updateVideoFavorites({
    required int videoAid,
    List<int> addFolderIds = const [],
    List<int> removeFolderIds = const [],
  });

  /// 批量從收藏夾移除
  ///
  /// 調用 POST /x/v3/fav/resource/batch-del
  Future<void> batchRemoveFromFolder({
    required int folderId,
    required List<int> videoAids,
  });

  /// 獲取視頻的 aid（從 bvid）
  ///
  /// 優先從 Track.bilibiliAid 緩存讀取
  /// 緩存未命中時調用 GET /x/web-interface/view?bvid={bvid}
  Future<int> getVideoAid(Track track);
}

/// 收藏夾數據模型
class BilibiliFavFolder {
  final int id;        // mlid（API 操作用這個）
  final String title;
  final int mediaCount;
  final bool isFavorited;  // 當前視頻是否已在此收藏夾
  final bool isDefault;    // 是否為默認收藏夾
}
```

### 3.5 BilibiliAuthInterceptor（Dio 攔截器）

```dart
/// 為 Bilibili API 請求自動注入認證 Cookie
class BilibiliAuthInterceptor extends Interceptor {
  final BilibiliAccountService _accountService;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final authCookies = await _accountService.getAuthCookieString();
    if (authCookies != null) {
      final existing = options.headers['Cookie'] as String? ?? '';
      options.headers['Cookie'] = existing.isEmpty
          ? authCookies
          : '$existing; $authCookies';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // 檢測 -101（未登錄）錯誤，嘗試刷新 Cookie 後重試
    if (_isAuthError(err.response)) {
      final refreshed = await _accountService.refreshCredentials();
      if (refreshed) {
        // 重試原始請求
        final retryResponse = await _accountService._dio.fetch(err.requestOptions);
        return handler.resolve(retryResponse);
      }
    }
    handler.next(err);
  }

  bool _isAuthError(Response? response) {
    final code = response?.data?['code'];
    return code == -101 || code == -111;
  }
}
```

---

## 4. Provider 層

### 4.1 account_provider.dart

```dart
/// Bilibili 帳號服務 Provider（單例）
final bilibiliAccountServiceProvider = Provider<BilibiliAccountService>((ref) {
  final isar = ref.watch(databaseProvider).requireValue;
  return BilibiliAccountService(isar: isar);
});

/// Bilibili 收藏夾服務 Provider
final bilibiliFavoritesServiceProvider = Provider<BilibiliFavoritesService>((ref) {
  final accountService = ref.watch(bilibiliAccountServiceProvider);
  return BilibiliFavoritesService(accountService: accountService);
});

/// Bilibili 帳號狀態 Provider（響應式）
final bilibiliAccountProvider = StateNotifierProvider<BilibiliAccountNotifier, Account?>((ref) {
  final isar = ref.watch(databaseProvider).requireValue;
  return BilibiliAccountNotifier(isar);
});

/// 是否已登錄 Bilibili（便捷 Provider）
final isBilibiliLoggedInProvider = Provider<bool>((ref) {
  final account = ref.watch(bilibiliAccountProvider);
  return account?.isLoggedIn ?? false;
});

/// 通用：根據平台獲取登錄狀態
final isLoggedInProvider = Provider.family<bool, SourceType>((ref, platform) {
  switch (platform) {
    case SourceType.bilibili:
      return ref.watch(isBilibiliLoggedInProvider);
    case SourceType.youtube:
      return false; // 未來實現
  }
});
```

---

## 5. 登錄流程設計

### 5.1 WebView 登錄（主要方式）

```
┌─────────────────────────────────────────────────┐
│  BilibiliLoginPage                              │
│                                                 │
│  ┌─ Tab: 網頁登錄 ─────────────────────────┐   │
│  │                                          │   │
│  │  InAppWebView                            │   │
│  │  url: passport.bilibili.com/login        │   │
│  │                                          │   │
│  │  onLoadStop: 檢測 URL 變化               │   │
│  │  → URL 包含 bilibili.com 且非 passport   │   │
│  │  → 提取 Cookies (SESSDATA, bili_jct...)  │   │
│  │  → JS 注入提取 localStorage refresh_token│   │
│  │  → 調用 loginWithCookies()               │   │
│  │  → fetchAndUpdateUserInfo()              │   │
│  │  → 返回帳號管理頁                        │   │
│  │                                          │   │
│  └──────────────────────────────────────────┘   │
│                                                 │
│  ┌─ Tab: 掃碼登錄 ─────────────────────────┐   │
│  │                                          │   │
│  │  QR Code 圖片（qr_flutter）              │   │
│  │  狀態提示：等待掃碼 / 已掃碼待確認 / 過期│   │
│  │                                          │   │
│  │  輪詢 Stream → 成功後同上流程            │   │
│  │                                          │   │
│  └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

### 5.2 WebView Cookie 提取流程

```dart
// InAppWebView onLoadStop callback
void _onPageLoaded(InAppWebViewController controller, WebUri? url) async {
  if (url == null) return;

  // 檢測是否已離開登錄頁（登錄成功後會跳轉）
  final host = url.host;
  if (host.contains('bilibili.com') && !host.contains('passport')) {
    // 提取 cookies
    final cookieManager = CookieManager.instance();
    final cookies = await cookieManager.getCookies(
      url: WebUri('https://www.bilibili.com'),
    );

    final sessdata = _findCookie(cookies, 'SESSDATA');
    final biliJct = _findCookie(cookies, 'bili_jct');
    final dedeUserId = _findCookie(cookies, 'DedeUserID');
    final dedeUserIdCkMd5 = _findCookie(cookies, 'DedeUserID__ckMd5');

    if (sessdata == null || biliJct == null || dedeUserId == null) {
      return; // 關鍵 cookie 缺失，可能不是真正的登錄成功
    }

    // 提取 refresh_token（存在 localStorage）
    final refreshToken = await controller.evaluateJavascript(
      source: "localStorage.getItem('ac_time_value')",
    ) as String?;

    // 保存並初始化
    await _accountService.loginWithCookies(
      sessdata: sessdata,
      biliJct: biliJct,
      dedeUserId: dedeUserId,
      dedeUserIdCkMd5: dedeUserIdCkMd5 ?? '',
      refreshToken: refreshToken ?? '',
    );

    if (mounted) {
      Navigator.pop(context, true); // 返回帳號管理頁
    }
  }
}
```

### 5.3 QR 碼登錄流程

```dart
// 生成 QR 碼
final qrData = await accountService.generateQrCode();
// qrData.url → 用 qr_flutter 渲染
// qrData.qrcodeKey → 用於輪詢

// 輪詢（每 2 秒）
accountService.pollQrCodeStatus(qrData.qrcodeKey).listen((result) {
  switch (result.status) {
    case QrCodeStatus.waiting:
      // 顯示「等待掃碼」
      break;
    case QrCodeStatus.scanned:
      // 顯示「已掃碼，請在手機上確認」
      break;
    case QrCodeStatus.expired:
      // 顯示「已過期」+ 重新生成按鈕
      break;
    case QrCodeStatus.success:
      // Cookies 已在 pollQrCodeStatus 內部保存
      // 獲取用戶信息並返回
      await accountService.fetchAndUpdateUserInfo();
      Navigator.pop(context, true);
      break;
  }
});
```

### 5.4 Cookie 自動刷新

```dart
/// 在 main.dart 啟動時調用
Future<void> _initAccountRefresh(ProviderContainer container) async {
  final accountService = container.read(bilibiliAccountServiceProvider);
  if (await accountService.isLoggedIn()) {
    final needsRefresh = await accountService.needsRefresh();
    if (needsRefresh) {
      final success = await accountService.refreshCredentials();
      if (!success) {
        // Cookie 刷新失敗，標記為需要重新登錄
        // UI 會在下次操作時提示
        logWarning('Bilibili cookie refresh failed, may need re-login');
      }
    }
  }
}
```

---

## 6. UI 設計

### 6.1 設置頁入口

在 `settings_page.dart` 的「外觀設置」section 之前添加：

```dart
// 帳號管理
_SettingsSection(
  title: t.settings.account,
  children: [
    ListTile(
      leading: const Icon(Icons.manage_accounts),
      title: Text(t.settings.accountManagement.title),
      subtitle: Text(t.settings.accountManagement.subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(RoutePaths.accountManagement),
    ),
  ],
),
const Divider(),
```

### 6.2 帳號管理頁面

```
┌─────────────────────────────────────┐
│ ← 帳號管理                          │
├─────────────────────────────────────┤
│                                     │
│  Bilibili                           │
│  ┌─────────────────────────────┐    │
│  │ 🅱 [頭像] 用戶暱稱          │    │
│  │         已登錄               │    │
│  │                    [登出]    │    │
│  └─────────────────────────────┘    │
│                                     │
│  YouTube                            │
│  ┌─────────────────────────────┐    │
│  │ ▶ 未登錄                    │    │
│  │                    [登錄]    │    │
│  └─────────────────────────────┘    │
│                                     │
│  （未來：網易雲、QQ音樂）           │
│                                     │
└─────────────────────────────────────┘
```

### 6.3 遠程收藏夾彈窗（add_to_remote_playlist_dialog.dart）

復用 `_AddToPlaylistSheet` 的 UI 結構，但數據源為遠程收藏夾。

```
┌─────────────────────────────────────┐
│ ─── 拖拽指示條 ───                   │
│                                     │
│ 添加到 Bilibili 收藏夾        [✕]   │
│                                     │
│ ┌─────────────────────────────┐     │
│ │ [封面] 歌曲標題              │     │
│ │        藝術家                │     │
│ └─────────────────────────────┘     │
│                                     │
│ ─── 收藏夾列表 (loading...) ───     │
│                                     │
│ ┌─────────────────────────────┐     │
│ │ [📁] 默認收藏夾 (85)    [✓] │ ← fav_state=1 已存在
│ │ [📁] 音樂收藏 (42)      [ ] │ ← fav_state=0
│ │ [📁] 私人收藏 (12)      [ ] │     │
│ └─────────────────────────────┘     │
│                                     │
│ ┌─────────────────────────────┐     │
│ │        [確認] 添加到 1 個    │     │
│ └─────────────────────────────┘     │
└─────────────────────────────────────┘
```

**與本地彈窗的差異：**

| 項目 | 本地彈窗 | 遠程彈窗 |
|------|---------|---------|
| 數據源 | `allPlaylistsProvider` | `BilibiliFavoritesService.getFavFolders()` |
| 已存在標記 | 本地 DB 查詢 | API `fav_state` 字段 |
| 提交操作 | `PlaylistService.addTrackToPlaylist()` | `BilibiliFavoritesService.updateVideoFavorites()` |
| 創建新歌單 | 支持 | 不支持（Bilibili 收藏夾需在 app 內創建） |
| Loading 狀態 | 本地，幾乎無延遲 | 網絡請求，需要 loading indicator |
| 錯誤處理 | 本地錯誤 | 登錄過期、權限不足、網絡錯誤 |

### 6.4 菜單集成

#### 6.4.1 歌單詳情頁（導入歌單）— 單曲菜單

在 `_PlaylistTrackItem._buildMenuItems()` 中添加：

```dart
List<PopupMenuEntry<String>> _buildMenuItems() => [
  // ... 現有菜單項 ...
  PopupMenuItem(value: 'play_next', ...),
  PopupMenuItem(value: 'add_to_queue', ...),
  if (!isMix) PopupMenuItem(value: 'download', ...),
  if (!isPartOfMultiPage) PopupMenuItem(value: 'add_to_playlist', ...),

  // ===== 新增：遠程操作 =====
  // 添加到遠程收藏夾（Bilibili 歌曲才顯示）
  if (track.sourceType == SourceType.bilibili)
    PopupMenuItem(
      value: 'add_to_remote',
      child: ListTile(
        leading: const Icon(Icons.cloud_upload_outlined),
        title: Text(t.remote.addToFavorites),
        contentPadding: EdgeInsets.zero,
      ),
    ),
  // 從遠程收藏夾移除（導入歌單 + 非 Mix 才顯示）
  if (isImported && !isMix && track.sourceType == SourceType.bilibili)
    PopupMenuItem(
      value: 'remove_from_remote',
      child: ListTile(
        leading: Icon(Icons.cloud_off_outlined, color: colorScheme.error),
        title: Text(t.remote.removeFromFavorites,
            style: TextStyle(color: colorScheme.error)),
        contentPadding: EdgeInsets.zero,
      ),
    ),

  if (!isImported) PopupMenuItem(value: 'remove', ...),
  PopupMenuItem(value: 'matchLyrics', ...),
];
```

#### 6.4.2 其他頁面（探索、搜索、首頁）— 單曲菜單

在 `_buildMenuItems()` 中添加（僅「添加到遠程」，無「移除」）：

```dart
// 添加到遠程收藏夾
if (track.sourceType == SourceType.bilibili)
  PopupMenuItem(
    value: 'add_to_remote',
    child: ListTile(
      leading: const Icon(Icons.cloud_upload_outlined),
      title: Text(t.remote.addToFavorites),
      contentPadding: EdgeInsets.zero,
    ),
  ),
```

#### 6.4.3 多選模式（SelectionModeAppBar）

擴展 `SelectionAction` enum：

```dart
enum SelectionAction {
  addToQueue,
  playNext,
  addToPlaylist,
  addToRemotePlaylist,       // 新增
  removeFromRemotePlaylist,  // 新增（僅導入歌單詳情頁）
  download,
  delete,
}
```

在 `SelectionModeAppBar` 的 `PopupMenuButton` 中添加對應菜單項。

**顯示條件：**
- `addToRemotePlaylist`：選中的 tracks 中有 Bilibili 歌曲時顯示
- `removeFromRemotePlaylist`：僅在導入歌單詳情頁 + 非 Mix + 選中的 tracks 為 Bilibili 歌曲時顯示

---

## 7. 操作流程

### 7.1 添加到遠程收藏夾

```
用戶點擊「添加到遠程收藏夾」
    │
    ▼
檢查 Bilibili 登錄狀態
    │
    ├─ 未登錄 → Toast「請先登錄 Bilibili 帳號」
    │           + 可選：跳轉到帳號管理頁
    │
    └─ 已登錄 ─┐
               ▼
    獲取 Track 的 aid
    （優先 Track.bilibiliAid 緩存，未命中則調 view API）
               │
               ▼
    調用 getFavFolders(videoAid: aid)
    （返回收藏夾列表 + 每個收藏夾的 fav_state）
               │
               ▼
    顯示 AddToRemotePlaylistDialog
    （已存在的收藏夾預勾選）
               │
               ▼
    用戶勾選/取消 → 計算 diff
    （新勾選 → addFolderIds，取消勾選 → removeFolderIds）
               │
               ▼
    調用 updateVideoFavorites(aid, addFolderIds, removeFolderIds)
               │
               ├─ 成功 → Toast「已更新收藏」
               │         + 刷新本地對應歌單（見 7.3）
               │
               ├─ -101 → Toast「登錄已過期，請重新登錄」
               │
               ├─ -403 → Toast「權限不足」
               │
               └─ 其他錯誤 → Toast「操作失敗：{message}」
```

### 7.2 從遠程收藏夾移除

```
用戶在導入歌單詳情頁點擊「從遠程移除」
    │
    ▼
確認對話框「確定要從 Bilibili 收藏夾中移除嗎？同時會從本地歌單中移除。」
    │
    ├─ 取消 → 返回
    │
    └─ 確認 ─┐
             ▼
    獲取 Track 的 aid
             │
             ▼
    從 Playlist.sourceUrl 解析收藏夾 mlid
    （復用現有的 _parseFavoritesId）
             │
             ▼
    調用 updateVideoFavorites(aid, removeFolderIds: [mlid])
    或 batchRemoveFromFolder(folderId: mlid, videoAids: [aid])（多選時）
             │
             ├─ 成功 → 同時從本地歌單移除（復用 PlaylistService.removeTrackFromPlaylist）
             │         + Toast「已從收藏夾移除」
             │         + 刷新歌單 Provider
             │
             └─ 失敗 → Toast 提示錯誤，不移除本地
```

### 7.3 操作後刷新本地歌單

```dart
/// 遠程操作成功後，刷新本地對應的導入歌單
Future<void> _refreshAffectedPlaylists(WidgetRef ref, List<int> folderIds) async {
  final playlists = ref.read(allPlaylistsProvider).valueOrNull ?? [];

  for (final playlist in playlists) {
    if (!playlist.isImported || playlist.sourceUrl == null) continue;
    if (playlist.importSourceType != SourceType.bilibili) continue;

    // 解析歌單的收藏夾 ID
    final fid = BilibiliSource.parseFavoritesId(playlist.sourceUrl!);
    if (fid != null && folderIds.any((id) => id.toString() == fid)) {
      // 觸發刷新
      ref.read(playlistListProvider.notifier)
          .invalidatePlaylistProviders(playlist.id);
    }
  }
}
```

### 7.4 重複檢測

在 `AddToRemotePlaylistDialog` 中：
- 打開彈窗時，API 已返回 `fav_state`，已存在的收藏夾自動打勾
- 用戶點擊已勾選（已存在）的收藏夾 → 取消勾選（表示要移除）
- 用戶點擊未勾選的收藏夾 → 勾選（表示要添加）
- 如果用戶沒有做任何改變就點確認 → Toast「沒有變更」並關閉

---

## 8. 錯誤處理

### 8.1 錯誤碼映射

```dart
String _mapBilibiliError(int code) {
  switch (code) {
    case -101: return t.remote.error.notLoggedIn;      // 「帳號未登錄，請重新登錄」
    case -111: return t.remote.error.csrfFailed;       // 「認證失敗，請重新登錄」
    case -403: return t.remote.error.noPermission;     // 「權限不足，非收藏夾擁有者」
    case -607: return t.remote.error.favoritesLimit;   // 「已達收藏上限」
    case 11010: return t.remote.error.contentNotFound;  // 「內容不存在」
    case 11201: return t.remote.error.alreadyFavorited; // 「已收藏」
    default: return t.remote.error.unknown(code: code); // 「操作失敗 ({code})」
  }
}
```

### 8.2 認證過期自動處理

`BilibiliAuthInterceptor` 在檢測到 `-101` 錯誤時：
1. 嘗試自動刷新 Cookie
2. 刷新成功 → 自動重試原始請求
3. 刷新失敗 → 拋出 `AuthExpiredException`，UI 層捕獲後顯示 Toast 並引導重新登錄

---

## 9. 路由配置

```dart
// RoutePaths
static const String accountManagement = '/settings/account';
static const String bilibiliLogin = '/settings/account/bilibili-login';

// RouteNames
static const String accountManagement = 'accountManagement';
static const String bilibiliLogin = 'bilibiliLogin';

// GoRoute 配置（在 settings 下嵌套）
GoRoute(
  path: 'account',
  name: RouteNames.accountManagement,
  builder: (context, state) => const AccountManagementPage(),
  routes: [
    GoRoute(
      path: 'bilibili-login',
      name: RouteNames.bilibiliLogin,
      builder: (context, state) => const BilibiliLoginPage(),
    ),
  ],
),
```

---

## 10. i18n 新增

新增 `remote.i18n.json`（zh-TW / zh-CN / en）：

```json
{
  "addToFavorites": "添加到遠程收藏夾",
  "removeFromFavorites": "從遠程收藏夾移除",
  "dialogTitle": "添加到 Bilibili 收藏夾",
  "noChanges": "沒有變更",
  "updated": "已更新收藏",
  "removed": "已從收藏夾移除",
  "removedAndLocal": "已從收藏夾和本地歌單移除",
  "confirmRemove": "確定要從 Bilibili 收藏夾中移除嗎？",
  "confirmRemoveContent": "同時會從本地歌單中移除。",
  "pleaseLogin": "請先登錄 Bilibili 帳號",
  "goToLogin": "前往登錄",
  "loading": "載入中...",
  "error": {
    "notLoggedIn": "帳號未登錄，請重新登錄",
    "csrfFailed": "認證失敗，請重新登錄",
    "noPermission": "權限不足，非收藏夾擁有者",
    "favoritesLimit": "已達收藏上限",
    "contentNotFound": "內容不存在",
    "alreadyFavorited": "已收藏",
    "unknown": "操作失敗 ({code})"
  }
}
```

新增 `account.i18n.json`：

```json
{
  "title": "帳號管理",
  "subtitle": "管理 Bilibili、YouTube 帳號",
  "notLoggedIn": "未登錄",
  "loggedIn": "已登錄",
  "login": "登錄",
  "logout": "登出",
  "logoutConfirm": "確定要登出 {platform} 帳號嗎？",
  "loginSuccess": "登錄成功",
  "logoutSuccess": "已登出",
  "refreshFailed": "認證刷新失敗，請重新登錄",
  "webLogin": "網頁登錄",
  "qrLogin": "掃碼登錄",
  "qrWaiting": "請使用 Bilibili 手機 App 掃描",
  "qrScanned": "已掃碼，請在手機上確認",
  "qrExpired": "二維碼已過期",
  "qrRefresh": "重新生成"
}
```

---

## 11. 實現順序（建議分 Phase）

### Phase 1：帳號基礎設施
1. 添加依賴（`flutter_inappwebview`, `qr_flutter`, `flutter_secure_storage`, `pointycastle`）
2. 創建 `Account` Isar 模型 + `BilibiliCredentials`
3. 實現 `BilibiliAccountService`（登錄、Cookie 存儲、刷新）
4. 實現 `BilibiliAuthInterceptor`
5. 創建 `account_provider.dart`

### Phase 2：登錄 UI
1. 創建 `AccountManagementPage`
2. 創建 `BilibiliLoginPage`（WebView + QR 碼兩個 Tab）
3. 設置頁添加入口
4. 路由配置
5. i18n（account.i18n.json）

### Phase 3：遠程收藏夾操作
1. 實現 `BilibiliFavoritesService`
2. Track 模型添加 `bilibiliAid` 字段 + 遷移
3. 創建 `AddToRemotePlaylistDialog`
4. i18n（remote.i18n.json）

### Phase 4：菜單集成
1. 歌單詳情頁菜單添加遠程操作
2. 探索/搜索/首頁菜單添加遠程操作
3. `SelectionModeAppBar` 擴展多選遠程操作
4. 操作後刷新邏輯

### Phase 5：Cookie 自動刷新
1. 實現完整的 Web Cookie 刷新流程（RSA 加密）
2. 啟動時自動檢查和刷新
3. 認證過期自動重試（Interceptor）

---

## 12. Bilibili API 速查

| 操作 | 端點 | 方法 | 關鍵參數 |
|------|------|------|---------|
| 生成 QR 碼 | `/x/passport-login/web/qrcode/generate` | GET | — |
| 輪詢 QR 碼 | `/x/passport-login/web/qrcode/poll` | GET | `qrcode_key` |
| 檢查 Cookie 刷新 | `/x/passport-login/web/cookie/info` | GET | Cookie |
| 刷新 Cookie | `/x/passport-login/web/cookie/refresh` | POST | `csrf`, `refresh_csrf`, `refresh_token` |
| 確認刷新 | `/x/passport-login/web/confirm/refresh` | POST | 新 Cookie + 舊 `refresh_token` |
| 用戶信息 | `/x/web-interface/nav` | GET | Cookie |
| 收藏夾列表 | `/x/v3/fav/folder/created/list-all` | GET | `up_mid`, `rid`(aid), `type=2` |
| 添加/移除收藏 | `/x/v3/fav/resource/deal` | POST | `rid`(aid), `type=2`, `add_media_ids`, `del_media_ids`, `csrf` |
| 批量刪除 | `/x/v3/fav/resource/batch-del` | POST | `media_id`, `resources`(aid:type), `csrf` |
| 視頻信息(含aid) | `/x/web-interface/view` | GET | `bvid` |

**所有 POST 請求必須帶 `csrf` 參數（= `bili_jct` cookie 值）。**

---

## 13. YouTube 擴展預留（未來）

| 項目 | 方案 |
|------|------|
| 登錄方式 | Google Device Authorization Flow（`google.com/device` + 代碼） |
| API | YouTube Data API v3（OAuth 2.0） |
| Token 持久化 | OAuth refresh token（Production 模式永久有效） |
| 播放列表操作 | `playlistItems.insert` / `playlistItems.delete` |
| 配額 | 10,000 units/day（insert/delete 各 50 units） |
| 注意 | WebView 登錄被 Google 封殺，不可用 |

擴展時只需：
1. 實現 `YouTubeAccountService extends AccountService`
2. 實現 `YouTubePlaylistService`（類似 `BilibiliFavoritesService`）
3. 在 `AccountManagementPage` 添加 YouTube 卡片
4. 菜單中根據 `track.sourceType == SourceType.youtube` 顯示對應操作
