# Bilibili 帳號管理 — 實現工作流

> 基於 `bilibili-account-remote-playlist.md` 設計文檔生成

## Phase 1：帳號基礎設施（無 UI 依賴）

### 1.1 添加依賴
- **文件**: `pubspec.yaml`
- **操作**: 添加 `flutter_inappwebview`, `qr_flutter`, `flutter_secure_storage`, `pointycastle`
- **驗收**: `flutter pub get` 成功
- **阻塞**: 無

### 1.2 創建 Account Isar 模型
- **文件**: `lib/data/models/account.dart`
- **操作**: 創建 `Account` collection（platform, userId, userName, avatarUrl, isLoggedIn, lastRefreshed, loginAt）
- **驗收**: `build_runner build` 生成 `account.g.dart`
- **阻塞**: 1.1

### 1.3 註冊 Account Schema
- **文件**: `lib/providers/database_provider.dart`
- **操作**: `Isar.open()` schemas 列表添加 `AccountSchema`；`_migrateDatabase()` 中添加 Account 初始化邏輯
- **驗收**: App 啟動不崩潰，Account collection 可讀寫
- **阻塞**: 1.2

### 1.4 創建 BilibiliCredentials 模型
- **文件**: `lib/services/account/bilibili_credentials.dart`
- **操作**: 創建 `BilibiliCredentials` 類（sessdata, biliJct, dedeUserId, dedeUserIdCkMd5, refreshToken, savedAt），含 `toJson()` / `fromJson()`
- **驗收**: JSON 序列化/反序列化正確
- **阻塞**: 無

### 1.5 創建 AccountService 抽象接口
- **文件**: `lib/services/account/account_service.dart`
- **操作**: 定義 `AccountService` 抽象類（isLoggedIn, getCurrentAccount, logout, refreshCredentials, needsRefresh）
- **驗收**: 編譯通過
- **阻塞**: 1.2

### 1.6 實現 BilibiliAccountService
- **文件**: `lib/services/account/bilibili_account_service.dart`
- **操作**:
  - 獨立 Dio 實例（帶 Referer/UA headers）
  - `loginWithCookies()` — 保存 credentials 到 `flutter_secure_storage`，更新 Account Isar 記錄
  - `generateQrCode()` — 調用 `/x/passport-login/web/qrcode/generate`
  - `pollQrCodeStatus()` — 返回 Stream，每 2 秒輪詢 `/x/passport-login/web/qrcode/poll`，成功時從 Set-Cookie 提取 cookies
  - `getAuthCookieString()` / `getCsrfToken()` / `getUserMid()` — 從 secure storage 讀取
  - `fetchAndUpdateUserInfo()` — 調用 `/x/web-interface/nav` 獲取暱稱/頭像，更新 Account
  - `logout()` — 清除 secure storage + 更新 Account.isLoggedIn = false
  - `needsRefresh()` — 調用 `/x/passport-login/web/cookie/info`
  - `refreshCredentials()` — 暫時留空（Phase 5 實現完整 RSA 流程）
- **驗收**: 單元測試 loginWithCookies → getAuthCookieString 返回正確值
- **阻塞**: 1.3, 1.4, 1.5

### 1.7 實現 BilibiliAuthInterceptor
- **文件**: `lib/services/account/bilibili_auth_interceptor.dart`
- **操作**: Dio Interceptor，`onRequest` 注入 Cookie header，`onError` 檢測 -101/-111 錯誤
- **驗收**: 攔截器正確合併 Cookie 到現有 header
- **阻塞**: 1.6

### 1.8 創建 account_provider.dart
- **文件**: `lib/providers/account_provider.dart`
- **操作**:
  - `bilibiliAccountServiceProvider` — Provider 單例
  - `bilibiliFavoritesServiceProvider` — Provider
  - `bilibiliAccountProvider` — StateNotifierProvider（監聽 Isar Account 變化）
  - `isBilibiliLoggedInProvider` — 便捷 bool Provider
  - `isLoggedInProvider` — family Provider（按 SourceType）
- **驗收**: Provider 可正常 watch/read
- **阻塞**: 1.6, 1.7

---

## Phase 2：登錄 UI

### 2.1 i18n — account 翻譯
- **文件**: `lib/i18n/{zh-TW,zh-CN,en}/account.i18n.json`
- **操作**: 添加帳號管理相關翻譯（title, subtitle, login, logout, qr 狀態等）
- **驗收**: `build_runner build` 生成 strings
- **阻塞**: 無

### 2.2 i18n — settings 翻譯擴展
- **文件**: `lib/i18n/{zh-TW,zh-CN,en}/settings.i18n.json`
- **操作**: 添加 `"account"` 和 `"accountManagement"` 翻譯 key
- **驗收**: `t.settings.account` 和 `t.settings.accountManagement.title` 可用
- **阻塞**: 無

### 2.3 路由配置
- **文件**: `lib/ui/router.dart`
- **操作**:
  - `RoutePaths` 添加 `accountManagement`, `bilibiliLogin`
  - `RouteNames` 添加對應 name
  - settings GoRoute 下嵌套 account 和 bilibili-login 路由
- **驗收**: `context.push(RoutePaths.accountManagement)` 導航正確
- **阻塞**: 2.4, 2.5

### 2.4 創建 AccountManagementPage
- **文件**: `lib/ui/pages/settings/account_management_page.dart`
- **操作**:
  - AppBar: 「帳號管理」
  - Bilibili 卡片：已登錄顯示頭像+暱稱+登出按鈕，未登錄顯示登錄按鈕
  - YouTube 卡片：顯示「未登錄」（灰色，暫不可操作）
  - 登出確認對話框
  - 使用 `bilibiliAccountProvider` 監聽狀態
- **驗收**: 頁面正確顯示登錄/未登錄狀態，登出功能正常
- **阻塞**: 1.8, 2.1

### 2.5 創建 BilibiliLoginPage
- **文件**: `lib/ui/pages/settings/bilibili_login_page.dart`
- **操作**:
  - TabBar: 「網頁登錄」/「掃碼登錄」
  - Tab 1 (WebView):
    - `InAppWebView` 載入 `https://passport.bilibili.com/login`
    - `onLoadStop` 檢測 URL 變化 → 提取 cookies + localStorage refresh_token
    - Loading indicator
  - Tab 2 (QR Code):
    - `qr_flutter` 渲染 QR 碼
    - 狀態文字（等待/已掃碼/過期）
    - 過期後「重新生成」按鈕
    - 輪詢 Stream 監聽
  - 登錄成功後 `fetchAndUpdateUserInfo()` → `Navigator.pop(context, true)`
- **驗收**: WebView 登錄和 QR 碼登錄都能成功獲取 cookies 並保存
- **阻塞**: 1.6, 2.1

### 2.6 設置頁添加入口
- **文件**: `lib/ui/pages/settings/settings_page.dart`
- **操作**: 在「外觀設置」section 之前添加「帳號管理」section（ListTile → push accountManagement）
- **驗收**: 設置頁顯示帳號管理入口，點擊跳轉正確
- **阻塞**: 2.3, 2.4

---

## Phase 3：遠程收藏夾操作

### 3.1 Track 模型添加 bilibiliAid 字段
- **文件**: `lib/data/models/track.dart`
- **操作**: 添加 `int? bilibiliAid` 字段
- **後續**: `build_runner build` 重新生成 `track.g.dart`
- **遷移**: `_migrateDatabase()` 中無需特殊處理（nullable，默認 null）
- **阻塞**: 無

### 3.2 BilibiliSource 暴露 parseFavoritesId
- **文件**: `lib/data/sources/bilibili_source.dart`
- **操作**: 將 `_parseFavoritesId` 改為 `static` public 方法（供遠程移除時解析 sourceUrl）
- **驗收**: 外部可調用 `BilibiliSource.parseFavoritesId(url)`
- **阻塞**: 無

### 3.3 實現 BilibiliFavoritesService
- **文件**: `lib/services/account/bilibili_favorites_service.dart`
- **操作**:
  - `getFavFolders({int? videoAid})` — GET `/x/v3/fav/folder/created/list-all`
  - `updateVideoFavorites({aid, addFolderIds, removeFolderIds})` — POST `/x/v3/fav/resource/deal`
  - `batchRemoveFromFolder({folderId, videoAids})` — POST `/x/v3/fav/resource/batch-del`
  - `getVideoAid(Track track)` — 優先 `track.bilibiliAid`，未命中調 view API 並緩存回 Track
  - 錯誤碼映射（-101, -403, -607, 11201 等）
- **驗收**: 手動測試 getFavFolders 返回正確數據
- **阻塞**: 1.6, 1.7, 3.1

### 3.4 i18n — remote 翻譯
- **文件**: `lib/i18n/{zh-TW,zh-CN,en}/remote.i18n.json`
- **操作**: 添加遠程操作相關翻譯（addToFavorites, removeFromFavorites, error codes 等）
- **驗收**: `build_runner build` 生成 strings
- **阻塞**: 無

### 3.5 創建 AddToRemotePlaylistDialog
- **文件**: `lib/ui/widgets/dialogs/add_to_remote_playlist_dialog.dart`
- **操作**:
  - `showAddToRemotePlaylistDialog({context, track/tracks})` 入口函數
  - UI 結構對齊 `add_to_playlist_dialog.dart`（DraggableScrollableSheet, 拖拽條, 標題, 歌曲信息, 列表, 確認按鈕）
  - 打開時 loading → 調用 `getFavFolders(videoAid)` → 顯示收藏夾列表
  - `fav_state=1` 的收藏夾預勾選
  - 勾選/取消 → 計算 diff → 確認按鈕文字動態更新
  - 提交時調用 `updateVideoFavorites()`
  - 錯誤處理：登錄過期 Toast、權限不足 Toast 等
  - 成功後刷新本地對應歌單
  - 多選模式：多個 tracks 時，逐個處理（收藏夾 API 是單視頻操作）
- **驗收**: 彈窗正確顯示收藏夾列表，勾選/取消/提交功能正常
- **阻塞**: 3.3, 3.4

---

## Phase 4：菜單集成

### 4.1 歌單詳情頁 — 單曲菜單
- **文件**: `lib/ui/pages/library/playlist_detail_page.dart`
- **操作**:
  - `_PlaylistTrackItem._buildMenuItems()` 添加 `add_to_remote` 和 `remove_from_remote` 菜單項
  - `_handleMenuAction()` 添加對應 case
  - `add_to_remote`: 檢查登錄 → 顯示 `AddToRemotePlaylistDialog`
  - `remove_from_remote`: 確認對話框 → 調用 `updateVideoFavorites` 移除 → 同時本地移除 → 刷新
  - 顯示條件：`track.sourceType == SourceType.bilibili`，移除還需 `isImported && !isMix`
- **驗收**: 菜單項正確顯示/隱藏，操作功能正常
- **阻塞**: 3.5

### 4.2 歌單詳情頁 — 多P組菜單
- **文件**: `lib/ui/pages/library/playlist_detail_page.dart`
- **操作**: 在 `_GroupHeader` 的菜單中添加 `add_to_remote`（組內所有 tracks 共享同一 bvid/aid）
- **驗收**: 多P組菜單顯示遠程操作
- **阻塞**: 4.1

### 4.3 探索頁菜單
- **文件**: `lib/ui/pages/explore/explore_page.dart`
- **操作**: `_buildMenuItems()` 添加 `add_to_remote`；`_handleMenuAction()` 添加對應 case
- **驗收**: 探索頁歌曲菜單顯示「添加到遠程收藏夾」
- **阻塞**: 3.5

### 4.4 搜索頁菜單
- **文件**: `lib/ui/pages/search/search_page.dart`
- **操作**: 同 4.3
- **阻塞**: 3.5

### 4.5 首頁菜單
- **文件**: `lib/ui/pages/home/home_page.dart`
- **操作**: 同 4.3
- **阻塞**: 3.5

### 4.6 SelectionModeAppBar 擴展
- **文件**: `lib/ui/widgets/selection_mode_app_bar.dart`
- **操作**:
  - `SelectionAction` enum 添加 `addToRemotePlaylist`, `removeFromRemotePlaylist`
  - `PopupMenuButton` 添加對應菜單項
  - `_handleMenuAction` 添加對應 case
  - `addToRemotePlaylist`: 過濾出 Bilibili tracks → 逐個顯示 dialog 或批量處理
  - `removeFromRemotePlaylist`: 確認 → 批量遠程移除 → 本地移除 → 刷新
  - 新增回調：`onRemoveFromRemote`（歌單詳情頁提供）
- **驗收**: 多選模式下遠程操作功能正常
- **阻塞**: 3.5

### 4.7 歌單詳情頁 — 多選模式集成
- **文件**: `lib/ui/pages/library/playlist_detail_page.dart`
- **操作**: `availableActions` 中根據條件添加 `addToRemotePlaylist` / `removeFromRemotePlaylist`
- **驗收**: 多選模式下遠程操作菜單正確顯示
- **阻塞**: 4.6

---

## Phase 5：Cookie 自動刷新

### 5.1 RSA 加密工具
- **文件**: `lib/services/account/bilibili_crypto.dart`
- **操作**:
  - `generateCorrespondPath(int timestamp)` — RSA-OAEP SHA-256 加密 `"refresh_{timestamp}"` → hex 編碼
  - 使用 Bilibili 公鑰（硬編碼）
  - 依賴 `pointycastle`
- **驗收**: 生成的 correspondPath 可成功請求 `/correspond/1/{path}`
- **阻塞**: 1.1

### 5.2 完整 Cookie 刷新流程
- **文件**: `lib/services/account/bilibili_account_service.dart`
- **操作**: 實現 `refreshCredentials()` 完整流程：
  1. `GET /x/passport-login/web/cookie/info` → 檢查 `refresh: true`
  2. `generateCorrespondPath(timestamp)` → correspondPath
  3. `GET /correspond/1/{correspondPath}` → 解析 HTML 提取 `refresh_csrf`
  4. `POST /x/passport-login/web/cookie/refresh` → 新 cookies + 新 refresh_token
  5. `POST /x/passport-login/web/confirm/refresh` → 確認（用新 cookie + 舊 refresh_token）
  6. 更新 secure storage 和 Account
- **驗收**: Cookie 刷新成功，新 cookies 可用於 API 調用
- **阻塞**: 5.1, 1.6

### 5.3 啟動時自動刷新
- **文件**: `lib/main.dart`
- **操作**: 在 app 初始化流程中調用 `_initAccountRefresh()`，檢查並刷新 Bilibili cookies
- **驗收**: App 啟動時自動刷新過期 cookies
- **阻塞**: 5.2

### 5.4 Interceptor 自動重試
- **文件**: `lib/services/account/bilibili_auth_interceptor.dart`
- **操作**: `onError` 中檢測 -101 → 調用 `refreshCredentials()` → 成功則重試原始請求
- **驗收**: API 調用遇到 -101 時自動刷新並重試
- **阻塞**: 5.2

---

## 依賴關係圖

```
Phase 1 (基礎設施)
  1.1 ─→ 1.2 ─→ 1.3
                  │
  1.4 ────────────┤
                  │
  1.5 ────────────┼─→ 1.6 ─→ 1.7 ─→ 1.8
                                       │
Phase 2 (登錄 UI)                      │
  2.1 ─────────────────────────────────┤
  2.2 ─────────────────────────────────┤
                                       │
  2.4 ←───────────────────────────────┘
  2.5 ←───────────────────────────────┘
  2.3 ←── 2.4, 2.5
  2.6 ←── 2.3, 2.4

Phase 3 (收藏夾操作)
  3.1 ──┐
  3.2 ──┼─→ 3.3 ──┐
  3.4 ─────────────┼─→ 3.5
                   │
Phase 4 (菜單集成) │
  4.1 ←────────────┘
  4.2 ←── 4.1
  4.3, 4.4, 4.5 ←── 3.5
  4.6 ←── 3.5
  4.7 ←── 4.6

Phase 5 (Cookie 刷新)
  5.1 ─→ 5.2 ─→ 5.3
              ─→ 5.4
```

---

## 關鍵風險與注意事項

1. **flutter_inappwebview Windows 支持**: 6.x 版本支持 Windows（WebView2），但需要確認穩定性。如果有問題，Windows 可以只提供 QR 碼登錄。

2. **Bilibili Cookie 提取時機**: WebView `onLoadStop` 可能在登錄成功前觸發多次。需要確保只在真正登錄成功（URL 離開 passport 域）時提取。

3. **bvid → aid 轉換**: 每次遠程操作都可能需要一次額外的 view API 調用（首次）。緩存到 `Track.bilibiliAid` 後不再重複調用。

4. **多選遠程操作**: 收藏夾 `resource/deal` API 是單視頻操作。多選時需要逐個調用，考慮添加進度提示。

5. **RSA 加密（Phase 5）**: `pointycastle` 的 RSA-OAEP 實現需要仔細測試。如果有問題，可以考慮用 TV QR 登錄的簡化 token 刷新作為替代。
