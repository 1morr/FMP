# Platform / Special Features Review

## 1. 审查范围

本次审查聚焦 Flutter 项目在 Android 与 Windows/桌面平台上的平台差异和特殊能力实现，未修改业务代码。重点阅读了以下代码与文档：

- 项目说明与记忆：`C:\Users\Roxy\Visual Studio Code\FMP\CLAUDE.md`、`C:\Users\Roxy\Visual Studio Code\FMP\.serena\memories\download_system.md`、`C:\Users\Roxy\Visual Studio Code\FMP\.serena\memories\update_system.md`、`C:\Users\Roxy\Visual Studio Code\FMP\.serena\memories\refactoring_lessons.md`
- 启动与平台初始化：`C:\Users\Roxy\Visual Studio Code\FMP\lib\main.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\app.dart`
- 音频后端与后台控制：`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\audio_provider.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\just_audio_service.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\media_kit_audio_service.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\audio_handler.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\windows_smtc_handler.dart`
- Android 原生配置：`C:\Users\Roxy\Visual Studio Code\FMP\android\app\src\main\AndroidManifest.xml`、`C:\Users\Roxy\Visual Studio Code\FMP\android\app\build.gradle.kts`
- Windows 原生、多窗口、单实例：`C:\Users\Roxy\Visual Studio Code\FMP\windows\runner\main.cpp`、`C:\Users\Roxy\Visual Studio Code\FMP\windows\runner\flutter_window.cpp`、`C:\Users\Roxy\Visual Studio Code\FMP\windows\flutter\generated_plugin_registrant.cc`
- 桌面能力：`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\platform\windows_desktop_service.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\providers\windows_desktop_provider.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\providers\desktop_settings_provider.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\widgets\custom_title_bar.dart`
- 歌词子窗口：`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\lyrics\lyrics_window_service.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\windows\lyrics_window.dart`
- 下载、路径与权限：`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\download\download_service.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\download\download_path_utils.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\download\download_path_manager.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\storage_permission_service.dart`
- 更新系统：`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\update\update_service.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\providers\update_provider.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\widgets\update_dialog.dart`

## 2. 总体结论

整体平台架构方向是清晰且值得保留的：移动端使用 `just_audio`/ExoPlayer，桌面端使用 `media_kit`/libmpv；Android 媒体通知通过 `audio_service` 统一入口，Windows 媒体键与系统媒体浮层走 SMTC；Windows 桌面能力集中在 `WindowsDesktopService`；歌词窗口使用 `desktop_multi_window` 独立 engine，并且已经针对全局静态 channel 插件做了选择性注册。

高风险问题主要集中在两类：

1. Android 11+ 存储权限判断过于乐观，可能把 Android 10 及以下也当成 Android 11+，导致下载目录选择流程请求错误权限。
2. Windows 便携版更新解压 ZIP 时没有做路径穿越校验，属于本地更新包处理边界上的安全风险。

中低风险问题主要是安装/更新鲁棒性、下载流请求头一致性、单实例激活 tray 隐藏窗口的边界，以及多窗口主窗口 handler 的生命周期。多数平台分层设计和已有折中（例如 Windows 下载 isolate、子窗口排除 tray/hotkey 插件、关闭隐藏而非销毁歌词窗口）建议保持不动。

## 3. 发现的问题列表

### 问题 1

- 等级：高
- 标题：Android 11+ 存储权限判断可能误判旧系统，导致目录选择请求错误权限
- 影响模块：Android 下载目录选择 / 外部存储权限
- 具体文件路径：`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\storage_permission_service.dart`
- 关键代码位置：`storage_permission_service.dart:20-27`、`storage_permission_service.dart:69-79`、`download_path_manager.dart:29-39`
- 问题描述：`StoragePermissionService._isAndroid11OrHigher()` 通过调用 `Permission.manageExternalStorage.status` 是否抛异常来判断 Android 11+，但 permission_handler 通常会在低版本也返回一个状态，而不是稳定抛异常。这样 Android 10 及以下可能走到 `Permission.manageExternalStorage.request()` 分支，而不是 `Permission.storage.request()`。
- 为什么这是问题：Android 10 及以下不应该依赖 `MANAGE_EXTERNAL_STORAGE`；错误分支可能直接打开无效设置页或返回 denied，导致用户无法选择下载目录，即使普通 storage 权限本可工作。
- 可能造成的影响：Android 10/9 等设备上自定义下载目录不可用；默认下载路径或同步流程可能被误判为权限不足；用户会看到权限说明但授权后仍失败。
- 推荐修改方向：使用可靠的 SDK 版本判断，例如 `device_info_plus` 获取 Android SDK int，或封装一个平台版本 provider；Android 11+ 才请求 `Permission.manageExternalStorage`，Android 10 及以下请求 `Permission.storage`。同时保留非 Android 平台返回 true 的行为。
- 修改风险：中。需要新增或使用已有设备信息依赖，并覆盖 Android 10、11、13+ 的权限流程。
- 是否值得立即处理：是。它直接影响 Android 下载核心功能。
- 分类：平台兼容性 / 权限
- 如果要改建议拆成几步执行：
  1. 增加可靠 SDK 版本获取函数，并为测试留出可注入入口。
  2. 调整 `hasStoragePermission()` 与 `requestStoragePermission()` 的版本分支。
  3. 在 Android 10 与 Android 11+ 设备/模拟器分别验证目录选择、写入 `.fmp_test` 和默认目录下载。

### 问题 2

- 等级：高
- 标题：Windows 便携版更新解压 ZIP 未防路径穿越
- 影响模块：应用内更新 / Windows 便携版
- 具体文件路径：`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\update\update_service.dart`
- 关键代码位置：`update_service.dart:413-424`
- 问题描述：`_downloadAndExtractZip()` 对 ZIP 中的 `file.name` 直接拼接到 `extractDir`：`final filePath = '$extractDir/${file.name}'`，随后创建文件并写入内容，没有校验规范化后的路径是否仍位于 `extractDir` 下。
- 为什么这是问题：如果下载到的 ZIP 资源被篡改或发布流程出错，包含 `../`、绝对路径、盘符路径等 entry 时，解压过程可能写出临时更新目录。虽然来源是 GitHub Release，但更新包属于外部输入，解压边界仍应防御。
- 可能造成的影响：覆盖用户临时目录外文件；进一步结合更新脚本可能覆盖应用目录外的文件；降低更新系统安全边界。
- 推荐修改方向：用 `p.normalize`/`p.canonicalize` 或 `Uri` 路径规则计算目标路径，确保目标路径以规范化后的 `extractDir` 为前缀；拒绝绝对路径、盘符路径和包含 `..` 后逃逸的 entry；必要时跳过非法 entry 并报错终止更新。
- 修改风险：低到中。只影响 Windows 便携版更新解压；需要用正常 ZIP 和恶意 entry 做回归。
- 是否值得立即处理：是。安全边界问题，修改范围小。
- 分类：安全 / 更新系统
- 如果要改建议拆成几步执行：
  1. 为 ZIP entry 目标路径增加规范化和前缀校验。
  2. 对目录 entry 和文件 entry 复用同一校验函数。
  3. 增加单元测试覆盖正常文件、`../evil.txt`、绝对路径、Windows 盘符路径。

### 问题 3

- 等级：中
- 标题：Windows 便携版更新脚本固定等待 2 秒，可能在进程未退出时覆盖失败
- 影响模块：应用内更新 / Windows 便携版自更新
- 具体文件路径：`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\update\update_service.dart`
- 关键代码位置：`update_service.dart:430-457`
- 问题描述：便携版更新生成 `fmp_updater.bat`，仅 `timeout /t 2` 后就执行 `xcopy` 覆盖应用目录并重启 exe。脚本没有等待原进程实际退出，也没有检查 `xcopy` 结果。
- 为什么这是问题：Windows 上 exe、dll、libmpv 或插件文件可能仍被当前进程占用，2 秒并非可靠同步点。覆盖失败后脚本仍会启动 exe，用户可能进入半更新状态或仍运行旧版本。
- 可能造成的影响：便携版更新偶发失败；应用目录部分文件更新、部分文件未更新；启动后版本不一致或缺少依赖。
- 推荐修改方向：生成脚本时传入当前 PID，循环 `tasklist /FI "PID eq <pid>"` 或 PowerShell `Wait-Process` 等待进程消失，再执行复制；复制后检查 `%ERRORLEVEL%`，失败时写日志并暂停/提示，不要无条件重启。
- 修改风险：中。脚本需兼容 Windows 默认环境、非管理员目录、路径含空格和非 ASCII 字符。
- 是否值得立即处理：是，若便携版更新是常用分发方式。
- 分类：平台鲁棒性 / 更新系统
- 如果要改建议拆成几步执行：
  1. 在 Dart 侧获取 PID 并写入更新脚本。
  2. 脚本先等待 PID 退出，再执行复制。
  3. 为复制失败增加日志和错误处理。
  4. 在便携版真实安装目录中演练更新流程。

### 问题 4

- 等级：中
- 标题：Android APK 安装只依赖 OpenFilex 返回值，缺少“允许安装未知应用”前置处理
- 影响模块：应用内更新 / Android 安装
- 具体文件路径：`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\update\update_service.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\android\app\src\main\AndroidManifest.xml`
- 关键代码位置：`update_service.dart:132-139`、`update_provider.dart:140-158`、`AndroidManifest.xml:13-14`
- 问题描述：Manifest 已声明 `REQUEST_INSTALL_PACKAGES`，但 `installApk()` 直接 `OpenFilex.open(filePath)`，没有在 Android 8+ 上检查当前应用是否被允许安装未知来源 APK，也没有引导用户到相应设置页。
- 为什么这是问题：很多设备首次安装更新 APK 时系统会拦截，用户需要开启“允许来自此来源”。OpenFilex 可能只是打开失败或系统返回错误，当前 UI 只能显示失败字符串，体验和可恢复性较差。
- 可能造成的影响：Android 用户下载完成后无法安装，尤其是首次使用内置更新时；重复点击仍失败。
- 推荐修改方向：在安装前通过平台通道或可用插件检查 `PackageManager.canRequestPackageInstalls()`；未授权时展示说明并跳转 `Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES`。授权后回到 App 保持 `readyToInstall` 状态，允许用户重试安装。
- 修改风险：中。需要 Android 原生代码或插件支持，并验证不同厂商 ROM 的设置返回路径。
- 是否值得立即处理：中高。若 Android 内置更新是主要升级路径，则建议尽快做。
- 分类：平台兼容性 / 更新系统 / UX
- 如果要改建议拆成几步执行：
  1. 增加 Android 安装权限检查封装。
  2. 在 `UpdateNotifier._triggerInstall()` 前执行检查和引导。
  3. 保持已下载 APK 复用逻辑不变。
  4. 在 Android 8+、13+ 设备验证首次安装和已授权安装。

### 问题 5

- 等级：中
- 标题：下载 isolate 请求头未复用播放侧认证 headers，部分需 Cookie 的直链可能下载失败
- 影响模块：下载系统 / 三方音源直链请求
- 具体文件路径：`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\download\download_service.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\audio_stream_manager.dart`
- 关键代码位置：`download_service.dart:604-611`、`download_service.dart:656-677`、`audio_stream_manager.dart:159-180`
- 问题描述：下载前获取音频流时会根据 `settings.useAuthForPlay(track.sourceType)` 构造 `authHeaders` 并传给 source，但真正由 `_isolateDownload()` 拉取 `audioUrl` 时只设置固定 `User-Agent` 和 `Referer`，没有合并 `authHeaders` 或播放侧 `getPlaybackHeaders()` 中的 Netease 认证 headers。
- 为什么这是问题：有些音频 URL 的签名已足够，有些平台/内容可能还要求 Cookie、Origin 或更完整 UA。播放侧对 Netease 会优先使用账号 headers，而下载侧丢失这些 headers，可能出现“能播放、不能下载”的平台差异。
- 可能造成的影响：Netease VIP/登录歌曲、Bilibili 登录态相关内容或某些 YouTube fallback 流下载失败；失败表现为 HTTP 403/401 或空内容。
- 推荐修改方向：在下载实际请求时构造“传给媒体 URL 的 headers”，至少合并固定 Referer/UA 与 authHeaders 中安全且必要的 Cookie/Origin；与 `AudioStreamManager.getPlaybackHeaders()` 的策略保持一致。注意不要把 source API 用的 headers 无脑传给所有 CDN，如果某些平台需要区分，应建立下载播放 headers helper。
- 修改风险：中。不同平台 CDN 对 Cookie/Origin 可能敏感，需要逐平台验证。
- 是否值得立即处理：建议处理，尤其是 Netease 登录播放已是默认策略。
- 分类：平台源兼容性 / 下载系统
- 如果要改建议拆成几步执行：
  1. 提取下载媒体请求 headers 构造函数，按 SourceType 明确规则。
  2. 合并必要 auth headers，并保留现有 Referer。
  3. 用 Bilibili、YouTube、Netease 登录/非登录样例验证下载。
  4. 记录 headers 策略到下载系统记忆或 CLAUDE.md。

### 问题 6

- 等级：中
- 标题：音频 URL 过期时间在播放侧固定为 1 小时，忽略 source 返回的真实 expiry
- 影响模块：播放 URL 生命周期 / 平台源差异
- 具体文件路径：`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\internal\audio_stream_delegate.dart`
- 关键代码位置：`audio_stream_delegate.dart:61-69`、`download_service.dart:615-619`
- 问题描述：播放侧 `ensureAudioStream()` 拿到 `AudioStreamResult.expiry` 后，仍固定 `track.audioUrlExpiry = DateTime.now().add(const Duration(hours: 1))`。下载侧同类逻辑则使用 `streamResult.expiry ?? const Duration(hours: 1)`。
- 为什么这是问题：项目文档明确 Netease URL 约 16 分钟过期，Bilibili 也会过期。播放侧缓存过长会让队列恢复、暂停后继续播放、重试等路径使用已过期 URL，增加 403 后 fallback/刷新成本，甚至在某些路径上播放失败。
- 可能造成的影响：Netease 暂停一段时间后恢复失败；Bilibili/YouTube 某些短期签名 URL 过期后仍被视为有效；平台问题表现不一致。
- 推荐修改方向：播放侧与下载侧一致，使用 `streamResult.expiry ?? const Duration(hours: 1)`。如果不同 source 的 expiry 语义不可靠，可在 source 层统一返回保守值。
- 修改风险：低。会更频繁刷新短有效期 URL，但符合业务预期。
- 是否值得立即处理：是。改动小且能降低过期 URL 相关问题。
- 分类：平台源兼容性 / 音频生命周期
- 如果要改建议拆成几步执行：
  1. 修改 `audio_stream_delegate.dart` 的 expiry 赋值。
  2. 检查 `hasValidAudioUrl` 使用逻辑是否按 `audioUrlExpiry` 判断。
  3. 用 Netease 和 Bilibili 播放、暂停、恢复流程验证。

### 问题 7

- 等级：中
- 标题：Windows 单实例激活依赖固定窗口标题，tray 隐藏或标题变化时可能找不到主窗口
- 影响模块：Windows 单实例 / 启动体验
- 具体文件路径：`C:\Users\Roxy\Visual Studio Code\FMP\windows\runner\main.cpp`、`C:\Users\Roxy\Visual Studio Code\FMP\windows\runner\flutter_window.cpp`
- 关键代码位置：`main.cpp:13-36`、`main.cpp:57-68`、`flutter_window.cpp:79-97`
- 问题描述：第二个进程检测到 mutex 已存在后，通过 `FindWindowW(kMainWindowClassName, kMainWindowTitle)` 或 `FindWindowW(nullptr, kMainWindowTitle)` 激活已有窗口。若 window_manager 修改了原生窗口标题、窗口处于 tray hide 状态且标题/类名不匹配，`ActivateExistingInstance()` 可能找不到窗口，第二进程退出但主窗口不显示。
- 为什么这是问题：单实例 mutex 本身阻止了第二实例启动，但激活逻辑不是强绑定到第一实例窗口句柄。自定义标题栏、window_manager、子窗口、多窗口都可能影响标题/窗口发现。
- 可能造成的影响：用户在应用已最小化到托盘时再次双击 exe，无任何可见反应；以为应用无法启动。
- 推荐修改方向：使用更可靠的进程间激活机制：注册唯一窗口消息 + HWND 存储、命名 pipe/local socket 通知主实例、或让主窗口创建唯一 message-only/hidden window 负责唤醒。至少要验证 tray hide 后 `FindWindowW` 仍能找到并 `ShowWindow`。
- 修改风险：中。涉及 Windows runner 原生代码和窗口生命周期。
- 是否值得立即处理：中。若用户频繁使用 tray/开机自启，建议处理。
- 分类：平台兼容性 / 单实例
- 如果要改建议拆成几步执行：
  1. 先手工验证当前 tray hide 后二次启动能否唤醒。
  2. 若失败，引入 IPC 唤醒通道或稳定窗口查找方式。
  3. 覆盖正常窗口、最小化、tray hide、启动参数 `--minimized` 场景。

### 问题 8

- 等级：中
- 标题：歌词子窗口 close fallback 会销毁子窗口，可能重新触发 window_manager 全局 channel 覆盖问题
- 影响模块：Windows 歌词子窗口 / 多窗口资源生命周期
- 具体文件路径：`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\windows\lyrics_window.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\lyrics\lyrics_window_service.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\windows\runner\flutter_window.cpp`
- 关键代码位置：`lyrics_window.dart:329-334`、`lyrics_window_service.dart:137-166`、`flutter_window.cpp:16-43`
- 问题描述：主设计是歌词窗口关闭时发送 `requestHide`，由主窗口 `LyricsWindowService.close()` 调用 `_controller.hide()`，避免销毁 engine。但 `_requestHide()` 在 channel 调用异常时 fallback 到 `windowManager.close()`，会真正关闭子窗口。下一次打开会创建新 engine 并重新注册 `window_manager`，而 `flutter_window.cpp` 注释已说明 window_manager 也存在全局 channel 事件链问题，只是通过 Dart 侧绕开。
- 为什么这是问题：异常 fallback 正好绕过了“hide instead of destroy”的稳定性设计。虽然 tray/hotkey 已排除，window_manager 仍可能覆盖主窗口 close/maximize 等 C++ 到 Dart 事件通道，导致主窗口关闭行为或窗口事件异常。
- 可能造成的影响：歌词窗口异常关闭后，主窗口关闭按钮、系统关闭、window_manager 事件链出现偶发异常；UI 图标状态与实际窗口状态不一致。
- 推荐修改方向：尽量不要在子窗口自行 `windowManager.close()`；fallback 可改为 `windowManager.hide()` 或仅忽略并保持窗口；主窗口通过 `onWindowsChanged` 处理强制关闭。若必须 close，应在重新创建后验证主窗口 window_manager 事件是否仍可用。
- 修改风险：低到中。用户点击关闭时需要保持“看起来已关闭”的行为。
- 是否值得立即处理：建议处理，符合项目已有多窗口经验。
- 分类：桌面多窗口 / 生命周期
- 如果要改建议拆成几步执行：
  1. 将 `_requestHide()` fallback 从 close 改为 hide 或更保守策略。
  2. 保持 `LyricsWindowService._checkWindowClosed()` 处理系统强制关闭。
  3. 验证歌词窗口打开/隐藏/再打开，以及主窗口关闭到托盘。

### 问题 9

- 等级：低到中
- 标题：主窗口歌词 channel handler 在隐藏窗口后保持注册，存在职责长期占用
- 影响模块：Windows 歌词子窗口通信
- 具体文件路径：`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\lyrics\lyrics_window_service.dart`
- 关键代码位置：`lyrics_window_service.dart:98-118`、`lyrics_window_service.dart:137-150`、`lyrics_window_service.dart:323-379`
- 问题描述：`open()` 时 `_registerMainWindowHandler()`，但 `close()` 只是 hide，不注销 handler；只有 `destroy()` 或检测到窗口真正关闭才 `_unregisterMainWindowHandler()`。这符合隐藏复用 engine 的设计，但 handler 在窗口隐藏期间仍然接收同名 channel 方法。
- 为什么这是问题：当前只有一个歌词 channel，风险不高；但若未来加入更多子窗口或复用 `WindowMethodChannel('lyrics_sync')`，隐藏状态下的 handler 仍可能响应旧窗口/迟到消息，引发状态更新或播放控制。
- 可能造成的影响：迟到的 `playPause`、`seekTo` 等命令在窗口隐藏后仍可能执行；未来扩展多窗口时 channel 命名冲突。
- 推荐修改方向：保留 hide 生命周期，但在 handler 内对 `_controller != null && !_isHidden` 或 windowId 做校验；或为每个窗口使用带 windowId 的 channel/消息参数。不要为了此问题改回销毁窗口。
- 修改风险：低。
- 是否值得立即处理：不急，可在下一次歌词窗口改动时顺手处理。
- 分类：桌面多窗口 / 通信边界
- 如果要改建议拆成几步执行：
  1. 在 handler 的控制命令前检查窗口状态或来源。
  2. 未来新增子窗口时将 channel 名称或消息体带上 windowId。
  3. 保持 hide 而非 destroy 的生命周期策略。


## 4. Android 专项结论

Android 侧总体设计正确：`main.dart:104-118` 在 Android/iOS 通过 `AudioService.init()` 初始化后台播放；`audio_provider.dart:2552-2558` 基于 `audioRuntimePlatformProvider` 选择移动端 `JustAudioService`；`just_audio_service.dart:506-510` 已经针对 just_audio `play()` 阻塞问题使用 `unawaited(_player.play())`，这是非常关键且应保持的时序折中。Manifest 中也具备媒体前台服务权限、网络权限、APK 安装权限和存储权限声明。

Android 需要优先关注两点：

1. 存储权限版本判断需要改为可靠 SDK 判断。当前通过 `Permission.manageExternalStorage.status` 是否抛异常来识别 Android 11+，风险较高，会直接影响自定义下载目录。
2. 内置 APK 安装需要补齐 Android 8+ “允许安装未知应用”的前置检查和引导。现在有 manifest 权限，但缺少运行时设置引导。

其他观察：

- Android 默认下载目录推导在 `download_path_utils.dart:137-145` 使用 `getExternalStorageDirectory()` 反推 `/storage/emulated/0/Music/FMP`，这是常见但偏脆弱的方案；如果要进一步增强，可以考虑 `external_path`/MediaStore/SAF 等更明确的公共 Music 目录方案。不过现有实现有 app documents fallback，可暂不作为高优先级问题。
- Android 媒体通知的 `FmpAudioHandler` 控制链条清晰，音乐与电台分别更新 handler。电台占用媒体控制后会通过 `restoreMediaControlOwnership()` 交还音乐控制，设计上是合理的。
- `AudioServiceConfig.androidStopForegroundOnPause = true` 可降低暂停时前台服务常驻感，但如果未来需要暂停后仍保持更强后台保活，需要重新评估通知生命周期。

## 5. Windows/桌面专项结论

Windows/桌面侧能力较丰富，且已经有若干成熟折中：

- `main.dart:124-127` 只在桌面初始化 `MediaKit.ensureInitialized()`，避免 Android 引入 media_kit 生命周期。
- `audio_provider.dart:2552-2558` 在桌面选择 `MediaKitAudioService`，并通过 `media_kit_audio_service.dart:224-260` 禁用视频轨、限制 demuxer/cache，适合纯音频播放器。
- `windows_smtc_handler.dart` 将媒体键/系统媒体浮层与音乐、电台状态对接，位置更新在 `audio_provider.dart:2324-2351` 做了 500ms 节流，方向合理。
- `windows/runner/flutter_window.cpp:16-43` 对 `desktop_multi_window` 子窗口选择性注册插件，明确排除了 `tray_manager` 与 `hotkey_manager`，并记录了 `window_manager` 全局 channel 风险。这是本项目桌面多窗口稳定性的关键设计，应保持。
- `windows_desktop_service.dart:286-383` 将全局快捷键注册统一串行到 `_syncHotkeys()`，避免多个 provider 竞态，是合理的 OS 全局状态同步方式。
- `download_service.dart:656-720` 使用 isolate 执行下载，配合主 isolate 1 秒 flush 进度，符合 Windows PostMessage 队列限制的经验。

Windows 侧建议优先处理更新系统的两个边界：便携版 ZIP 路径穿越校验、更新脚本等待进程退出/检查复制结果。其次验证单实例在 tray hide 下的唤醒能力，必要时用 IPC 替代固定标题 `FindWindowW`。

桌面多窗口方面，当前“隐藏歌词窗口而不是销毁”是正确方向。后续改动重点应是避免异常 fallback 调 `windowManager.close()`，以及新增插件时继续检查 C++ 插件是否存在全局静态 channel。

## 6. 当前合理折中 / 建议保持不动的点

1. 移动端 `JustAudioService`、桌面端 `MediaKitAudioService` 的后端分离应保持。它降低 Android 体积/内存，同时保留桌面音频设备切换和 libmpv 兼容性。
2. `MediaKit.ensureInitialized()` 仅桌面调用应保持，避免 Android 走不需要的 media_kit 初始化。
3. `JustAudioService.playUrl()` / `playFile()` 使用 `unawaited(_player.play())` 应保持。它解决了 Android 首次播放时 UI 长时间卡在 loading 的后端语义差异。
4. UI 只经 `AudioController` 控制音频、底层只由 `FmpAudioService` 抽象暴露能力，这条边界应继续保持。
5. Windows 子窗口选择性注册插件应保持，尤其不要让 `tray_manager`、`hotkey_manager` 注册到歌词子窗口。新增 Windows 插件时必须检查是否有全局静态 channel。
6. 歌词窗口关闭时隐藏而非销毁应保持。它是规避多 engine + 全局 channel 事件链问题的合理折中。
7. Windows 下载走 isolate、进度只在内存中高频更新，完成/暂停/失败再落 DB，应保持。它针对 Windows PostMessage 与 Isar watch 高频重建问题非常有效。
8. Windows 全局快捷键通过 `_syncHotkeys()` 串行同步应保持。OS 全局状态不适合由多个 provider 各自 register/unregister。
9. 电台与音乐共享播放器时拆分 retained context 和 active ownership 的设计应保持。`RadioController` 用 active ownership 决定是否接管播放器事件，能避免状态归属错乱。
10. Windows 自定义标题栏关闭按钮直接调用 `WindowsDesktopService.handleCloseIntent()` 的设计应保持。它不依赖可能被子窗口影响的 `window_manager` close 事件链。
