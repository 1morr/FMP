# 平台专项审查报告

## 审查范围

本次审查聚焦跨平台行为与平台专项实现，主要覆盖以下内容：
- Android 与 Windows 的启动流程、平台初始化与主入口。
- 音频后端分离设计：Android `just_audio` / Windows `media_kit`。
- Android 后台播放、通知栏媒体控制、`audio_service` 集成。
- Windows SMTC、系统托盘、全局快捷键、窗口管理、单实例处理。
- `desktop_multi_window` 子窗口、歌词窗口、插件注册与资源释放。
- 电台/直播与歌曲播放共用全局媒体控制时的所有权切换。

本次实际检查的重点文件包括：
- `lib/main.dart`
- `lib/app.dart`
- `lib/services/audio/audio_provider.dart`
- `lib/services/audio/audio_handler.dart`
- `lib/services/audio/just_audio_service.dart`
- `lib/services/audio/media_kit_audio_service.dart`
- `lib/services/audio/windows_smtc_handler.dart`
- `lib/services/radio/radio_controller.dart`
- `lib/services/platform/windows_desktop_service.dart`
- `lib/services/lyrics/lyrics_window_service.dart`
- `lib/ui/windows/lyrics_window.dart`
- `lib/ui/widgets/custom_title_bar.dart`
- `windows/runner/main.cpp`
- `windows/runner/flutter_window.cpp`
- `android/app/src/main/AndroidManifest.xml`

## 总体结论

- Critical / High / Medium / Low：当前未发现需要立刻阻断发布的 Critical 级问题。

本轮审查结论如下：
- 平台后端分离总体合理，Android / Windows 的职责边界基本清楚。
- Android 后台播放接入方式正确，Manifest 配置也基本完整。
- Windows 单实例、托盘、热键、子窗口插件排除策略的整体方向是对的。
- 需要重点关注 1 个 High 问题：电台播放接管全局媒体控制回调后，没有恢复音乐播放回调所有权。
- 另外有 2 个 Medium 问题：Windows 多窗口关闭链路仍有脆弱点；Windows 全局语义树被禁用导致无障碍能力整体关闭。

## 发现的问题列表

### 问题 1
- 严重级别：High
- 标题：电台播放覆盖全局媒体控制回调后，未在返回音乐播放时恢复回调所有权
- 影响模块：Android 通知栏媒体控制、Windows SMTC、歌曲/电台共享播放器切换
- 具体文件路径：
  - `lib/services/audio/audio_provider.dart`
  - `lib/services/radio/radio_controller.dart`
- 必要时附关键代码位置：
  - `lib/services/audio/audio_provider.dart:1278-1317`
  - `lib/services/radio/radio_controller.dart:288-305`
  - `lib/services/radio/radio_controller.dart:320-335`
  - `lib/services/radio/radio_controller.dart:498-528`
  - `lib/services/radio/radio_controller.dart:550-579`
- 问题描述：
  `AudioController` 在初始化时为 Android `FmpAudioHandler` 和 Windows `WindowsSmtcHandler` 绑定歌曲播放回调；但 `RadioController` 在播放电台时会覆写同一组全局回调。后续 `stop()` / `pause()` / `returnToMusic()` 只处理状态清理，没有把这些回调重新绑定回音乐播放控制。
- 为什么这是问题：
  这些媒体控制对象是全局单例式通道，不是局部页面状态。电台接管后如果不显式归还控制权，后续通知栏按钮、媒体键、SMTC 按钮仍可能落到 `RadioController` 的闭包上，而不是音乐播放控制。
- 可能造成的影响：
  - 电台退出后，Android 通知栏播放/暂停、上一首/下一首行为可能异常。
  - Windows SMTC 按钮可能继续指向电台控制逻辑，导致无响应或控制错误对象。
  - 共享播放器在“歌曲 → 电台 → 返回歌曲”链路上出现平台相关回归，且这类问题通常只会在真实平台交互中暴露。
- 推荐修改方向：
  引入统一的“全局媒体控制所有权”切换层，明确当前由音乐还是电台持有控制权；至少要在电台停止、暂停并归还音乐控制时，显式重新执行音乐侧的 handler / SMTC 回调绑定。
- 修改风险：Medium
- 是否值得立即处理：是
- 分类：应立即修改
- 如果要改，建议拆成几步执行：
  1. 把 Android `audioHandler` 与 Windows `windowsSmtcHandler` 的回调绑定提炼为统一的“控制权切换”入口。
  2. 在 `RadioController` 接管时调用“切到电台控制”，在 `stop()` / `returnToMusic()` 时调用“切回音乐控制”。
  3. 补一组最小平台回归测试/手工验证清单，覆盖“歌曲 → 电台 → 返回歌曲”后的通知栏与 SMTC 按钮行为。

### 问题 2
- 严重级别：Medium
- 标题：Windows 多窗口场景下对 `window_manager` 关闭事件链仍存在脆弱依赖
- 影响模块：Windows 主窗口关闭、最小化到托盘、安装器触发关闭、多窗口生命周期
- 具体文件路径：
  - `windows/runner/flutter_window.cpp`
  - `lib/ui/widgets/custom_title_bar.dart`
  - `lib/services/platform/windows_desktop_service.dart`
  - `lib/services/lyrics/lyrics_window_service.dart`
- 必要时附关键代码位置：
  - `windows/runner/flutter_window.cpp:16-23`
  - `windows/runner/flutter_window.cpp:38-42`
  - `lib/ui/widgets/custom_title_bar.dart:90-100`
  - `lib/services/platform/windows_desktop_service.dart:473-487`
  - `lib/services/lyrics/lyrics_window_service.dart:137-166`
  - `lib/services/lyrics/lyrics_window_service.dart:291-315`
- 问题描述：
  当前已经正确把 `tray_manager` 与 `hotkey_manager` 排除在子窗口插件注册之外，但子窗口仍保留了 `window_manager`。代码里也明确承认 `window_manager` 在多窗口下存在同类全局 channel 脆弱性，因此目前只对“自定义标题栏关闭按钮”做了绕过处理；而 Alt+F4、系统关闭、安装器触发关闭等链路，仍然依赖 `onWindowClose()` 等事件回调正常送达。
- 为什么这是问题：
  这意味着当前修复是“部分路径绕过”，不是“关闭链路彻底去脆弱化”。如果子窗口生命周期与主窗口事件通道再次发生覆盖或失效，仍可能出现某些关闭路径不一致的问题。
- 可能造成的影响：
  - 某些关闭方式不能稳定触发“最小化到托盘”。
  - 安装器需要关闭应用时，行为可能与预期不一致。
  - 该问题往往只在 Windows 真机、多窗口打开过、且使用非自定义按钮关闭时出现，排查成本较高。
- 推荐修改方向：
  将主窗口关闭拦截进一步下沉到 Win32 runner 或更稳定的原生层入口，避免主关闭路径继续依赖易受多窗口影响的 Dart 侧 `window_manager` 事件链；现有标题栏按钮直连 `handleCloseButton()` 的做法可以保留，但不应成为唯一保障。
- 修改风险：Medium
- 是否值得立即处理：否（除非近期已收到 Windows 关闭路径异常反馈）
- 分类：建议列入后续重构计划
- 如果要改，建议拆成几步执行：
  1. 先补一份 Windows 关闭路径回归清单：标题栏按钮、Alt+F4、任务栏关闭、安装器关闭。
  2. 确认哪条路径仍依赖脆弱事件链，并把该路径迁移到原生关闭拦截。
  3. 保留现有 Dart 侧兜底逻辑，完成迁移后再评估是否可以收敛重复处理代码。

### 问题 3
- 严重级别：Medium
- 标题：Windows 端通过全局 `ExcludeSemantics` 规避引擎问题，导致无障碍能力整体关闭
- 影响模块：Windows 主应用界面、歌词子窗口、屏幕阅读器/辅助技术支持
- 具体文件路径：
  - `lib/app.dart`
  - `lib/ui/windows/lyrics_window.dart`
- 必要时附关键代码位置：
  - `lib/app.dart:125-133`
  - `lib/ui/windows/lyrics_window.dart:92-108`
- 问题描述：
  当前 Windows 主应用与歌词子窗口都使用了全局 `ExcludeSemantics`，以规避 Flutter Windows 的 AXTree / accessibility bridge 问题。这样虽然能绕开已知引擎异常，但也会把语义树整体关闭。
- 为什么这是问题：
  这是一个真实的平台能力回退，而不是纯实现细节。它会直接影响 Windows 的无障碍可用性，等于把辅助功能支持整体牺牲掉了。
- 可能造成的影响：
  - 屏幕阅读器无法正确读取界面结构与控件语义。
  - Windows 端的可访问性体验明显弱于 Android 端。
  - 后续若要补无障碍支持，修复成本会高于现在尽早收敛 workaround 范围。
- 推荐修改方向：
  把 workaround 从“全局关闭 semantics”收缩到具体有问题的区域、窗口或控件层；如果暂时做不到，至少应将其视为临时兼容方案，并记录条件与退出策略。
- 修改风险：Medium
- 是否值得立即处理：否（除非近期有明确 Windows 无障碍要求）
- 分类：建议列入后续重构计划
- 如果要改，建议拆成几步执行：
  1. 先定位真正触发 AXTree 问题的窗口/Overlay/控件范围。
  2. 将 `ExcludeSemantics` 缩小到最小必要区域，而不是包裹整个应用或整个歌词窗口。
  3. 在 Windows 真机上补一轮辅助技术回归验证，确认不会重新引入原始崩溃或报错。

## 当前设计可接受 / 建议保持不动

### 设计项 1：Windows 单实例 + `multi_window` 豁免
- 相关文件：`windows/runner/main.cpp:13-18`, `windows/runner/main.cpp:57-67`
- 结论：建议保持不动。
- 原因：主实例互斥与 `desktop_multi_window` 子窗口启动豁免同时成立，设计方向正确，符合桌面多窗口应用的基本要求。

### 设计项 2：Android `just_audio` / 桌面 `media_kit` 的后端分离
- 相关文件：`lib/services/audio/audio_provider.dart:2580-2587`, `lib/main.dart:124-126`
- 结论：建议保持不动。
- 原因：平台能力差异被清晰下沉到后端实现层；桌面设备切换能力也只在 `media_kit` 侧实现，没有出现 UI 直接依赖具体后端的问题。

### 设计项 3：Android 后台播放使用 `audio_service`
- 相关文件：`lib/main.dart:104-122`, `lib/services/audio/audio_handler.dart:12-209`, `android/app/src/main/AndroidManifest.xml:31-70`
- 结论：建议保持不动。
- 原因：初始化方式、通知控制抽象、Manifest 中 Activity / Service / Receiver 的声明是成体系的，属于当前仓库中比较稳的 Android 平台集成。

### 设计项 4：Windows 热键串行同步与子窗口插件排除策略
- 相关文件：`lib/services/platform/windows_desktop_service.dart:286-320`, `windows/runner/flutter_window.cpp:16-23`, `windows/runner/flutter_window.cpp:40-42`
- 结论：建议保持不动。
- 原因：对 OS 全局状态采用串行同步是正确做法；对子窗口排除 `tray_manager` / `hotkey_manager` 也是必要且一致的保护策略，整体方向没有问题。
