# FMP 音频系统架构

## 三层架构

```
┌─────────────────────────────────────────────────────────────┐
│                         UI Layer                             │
│   player_page.dart, mini_player.dart, queue_page.dart       │
│                            │                                 │
│                            ▼                                 │
│              audioControllerProvider (只使用这个)             │
└─────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                    AudioController                           │
│              (lib/services/audio/audio_provider.dart)        │
│                                                              │
│  职责：                                                       │
│  - 协调 AudioService 和 QueueManager                         │
│  - 管理 PlayerState 状态                                     │
│  - 处理业务逻辑（临时播放、静音记忆等）                          │
│  - 监听事件并更新 UI 状态                                      │
│                                                              │
│  关键方法：                                                    │
│  - play/pause/stop/togglePlayPause - 委托给 AudioService     │
│  - seekTo/seekForward/seekBackward - 委托给 AudioService     │
│  - setVolume - 委托 + 保存到持久化                            │
│  - toggleMute - 记忆音量的静音切换                             │
│  - playTrack/playAll/playPlaylist - 队列播放                 │
│  - playTemporary - 临时播放（不影响队列）                       │
│  - next/previous - 上下首切换                                 │
│  - addToQueue/addNext/removeFromQueue - 队列操作             │
│  - toggleShuffle/setLoopMode - 播放模式                       │
└─────────────────────────────────────────────────────────────┘
           │                              │
           ▼                              ▼
┌─────────────────────────┐    ┌─────────────────────────────┐
│  MediaKitAudioService   │    │       QueueManager          │
│(media_kit_audio_service)│    │    (queue_manager.dart)     │
│                         │    │                             │
│ 职责：                   │    │ 职责：                       │
│ - 封装 media_kit        │    │ - 管理播放队列               │
│ - 单曲播放控制           │    │ - Shuffle 逻辑              │
│ - 音频会话处理           │    │ - Loop 模式                 │
│                         │    │ - 队列持久化                 │
│ 关键方法：               │    │ - 预取下一首 URL             │
│ - playUrl/playFile     │    │                             │
│ - setUrl/setFile       │    │ 关键方法：                    │
│ - play/pause/stop      │    │ - playSingle/playAll        │
│ - seekTo               │    │ - add/addAll/addNext        │
│ - setVolume            │    │ - removeAt/move/clear       │
│                         │    │ - toggleShuffle             │
│ 不包含：                 │    │ - setLoopMode               │
│ - toggleMute (已移除)   │    │ - ensureAudioUrl            │
└─────────────────────────┘    │ - prefetchNext              │
           │                              │
           ▼                              ▼
┌─────────────────────────┐    ┌─────────────────────────────┐
│       media_kit         │    │      Isar Database          │
│    (Player)             │    │   (QueueRepository, etc.)   │
│  原生 httpHeaders 支持   │    └─────────────────────────────┘
│  无需代理，音频流正常     │
└─────────────────────────┘
```

## 重要设计决策

### 0. 播放歌曲与队列分离（2025年1月重构）
**问题：** 原设计中 `_updateQueueState()` 会同时更新 `currentTrack`，导致在临时播放或添加到空队列时，UI 显示与实际播放不一致。

**解决方案：** 引入 `playingTrack` 和 `queueTrack` 两个独立字段：
```dart
class PlayerState {
  /// 实际正在播放的歌曲（UI 显示用）
  final Track? playingTrack;
  
  /// 队列中当前位置的歌曲（可能与 playingTrack 不同）
  final Track? queueTrack;
  
  /// 向后兼容的 getter
  Track? get currentTrack => playingTrack;
}
```

**关键变化：**
- `_playingTrack` 由 `_updatePlayingTrack()` 单独管理
- `_updateQueueState()` 只更新队列相关状态，不再修改 `playingTrack`
- `_playTrack()`, `playTemporary()`, `_prepareCurrentTrack()`, `_restoreSavedState()` 在成功播放后调用 `_updatePlayingTrack()`
- `stop()` 调用 `_clearPlayingTrack()` 清除播放状态

**好处：**
- UI 显示与实际播放始终一致
- 添加到队列不会影响当前播放显示
- 临时播放、恢复队列等场景更加健壮

### 0.1 "脱离队列"状态检测（2026-01-19 统一重构）
当 `playingTrack` 与 `queueTrack` 不一致时，称为"脱离队列"状态。

**统一检测逻辑 `_isPlayingOutOfQueue` getter：**
```dart
bool get _isPlayingOutOfQueue {
  final queueTrack = _queueManager.currentTrack;
  final queue = _queueManager.tracks;
  
  // 1. 临时播放模式
  // 2. 脱离队列模式（如队列清空后继续播放）
  // 3. 正在播放的歌曲与队列当前位置不一致
  // 4. 正在播放但队列当前位置为空（队列不为空但索引不在范围内）
  return _context.mode == PlayMode.temporary ||
         _context.mode == PlayMode.detached ||
         (_playingTrack != null && queueTrack != null && _playingTrack!.id != queueTrack.id) ||
         (_playingTrack != null && queueTrack == null && queue.isNotEmpty);
}
```

**发生场景：**
1. **临时播放模式** - `_context.mode == PlayMode.temporary`
2. **脱离队列模式** - `_context.mode == PlayMode.detached`（如队列清空后继续播放，之后又添加新歌曲）
3. **其他不一致情况** - `_playingTrack.id != queueTrack.id`

**行为：**
- `upcomingTracks` 显示队列从索引 0 开始的歌曲
- 点击"下一首"/"上一首"调用 `_returnToQueue()` 回到队列播放
- `canPlayNext`/`canPlayPrevious` 只要队列不为空就为 true

**`_returnToQueue()` 方法：**
```dart
Future<void> _returnToQueue() async {
  _context = _context.copyWith(
    mode: PlayMode.queue,
    savedQueueIndex: null,
    savedPosition: null,
    savedWasPlaying: null,
  );
  await _playFirstInQueue();
}
```

### 1. 委托模式
AudioController 中的基础播放方法（play, pause, seekTo 等）是对 AudioService 的委托：
```dart
// AudioController
Future<void> play() async {
  await _audioService.play();  // 直接委托
}

Future<void> setVolume(double volume) async {
  await _audioService.setVolume(volume);  // 委托
  state = state.copyWith(volume: volume); // 更新状态
  await _queueManager.saveVolume(volume); // 持久化
}
```

**为什么这样设计：**
- UI 层只需依赖 AudioController
- AudioService 保持简单，只负责播放器操作
- AudioController 可以添加业务逻辑

### 2. 临时播放功能（PlaybackContext 重构 2026-01-19）
**用途：** 搜索页/歌单页点击歌曲时，临时播放该歌曲，播放完成后恢复原队列位置

**单曲循环优先：** 如果设置了单曲循环模式（`LoopMode.one`），临时播放的歌曲会继续循环播放，而不是恢复原队列。只有在非单曲循环模式下，临时播放结束后才会恢复原队列

**设计决策：**
- **不保存队列内容** - 只保存索引和位置，恢复时直接使用当前队列
- **用户可在临时播放期间修改队列** - 修改会被保留，不会被覆盖
- **索引自动限制** - 恢复时如果保存的索引超出当前队列范围，会 clamp 到有效范围

**使用 `_PlaybackContext` 管理状态：**
```dart
/// 播放上下文 - 统一管理所有播放状态
class _PlaybackContext {
  final PlayMode mode;           // queue, temporary, detached
  final int activeRequestId;     // 当前活动的请求 ID（0 表示无活动请求）
  final int? savedQueueIndex;    // 临时播放保存的队列索引
  final Duration? savedPosition; // 临时播放保存的播放位置
  final bool? savedWasPlaying;   // 临时播放保存的播放状态
  
  bool get isTemporary => mode == PlayMode.temporary;
  bool get isInLoadingState => activeRequestId > 0;
  bool get hasSavedState => savedQueueIndex != null;
  
  _PlaybackContext copyWith({...});
}

/// 播放模式
enum PlayMode {
  queue,      // 正常队列播放
  temporary,  // 临时播放（播放完成后恢复）
  detached,   // 脱离队列（如队列清空后继续播放）
}
```

**流程：**
1. `playTemporary(track)` - 设置 `_context` 为 `PlayMode.temporary` 并保存当前索引和位置
2. 歌曲完成时 `_onTrackCompleted` 检测到 `_context.isTemporary`
3. `_restoreSavedState()` - 直接使用当前队列，恢复到保存的索引位置，回退10秒，如果之前在播放则继续播放

**重要：`_restoreSavedState()` 必须使用 `_playRequestId` 机制**

`_restoreSavedState()` 有自己的 URL 获取逻辑，必须：
1. 开始时递增 `_playRequestId` 来取消任何正在进行的播放请求
2. URL 获取后检查 `_isSuperseded(requestId)`
3. setUrl 后再次检查 `_isSuperseded(requestId)`

这样可以防止以下场景的竞态条件：
- 临时播放正在获取 URL → 用户点击"下一首" → 恢复操作取消临时播放
- 恢复操作正在获取 URL → 用户点击新歌曲 → 新歌曲取消恢复操作

### 3. 静音切换
**实现位置：** 仅在 AudioController（不在 AudioService）

```dart
double _volumeBeforeMute = 1.0;

Future<void> toggleMute() async {
  if (state.volume > 0) {
    _volumeBeforeMute = state.volume;
    await setVolume(0);
  } else {
    await setVolume(_volumeBeforeMute);
  }
}
```

**注意：** UI 必须调用 `controller.toggleMute()`，而不是直接 `setVolume(0)` 和 `setVolume(1.0)`

### 4. Shuffle 模式
**实现位置：** QueueManager

**关键：**
- `_shuffleOrder` - 随机顺序索引列表
- `_shuffleIndex` - 当前在随机顺序中的位置
- 清空队列后添加歌曲时会自动重新生成 shuffle order
- `getUpcomingTracks(count)` - 获取接下来要播放的歌曲，已考虑 shuffle 模式
- `PlayerState.upcomingTracks` - UI 应使用此字段显示"接下来播放"，而非手动计算

**UI 显示下一首时必须使用 `upcomingTracks`：**
```dart
// ✅ 正确：使用 upcomingTracks
final nextTrack = playerState.upcomingTracks.isNotEmpty
    ? playerState.upcomingTracks.first
    : null;

// ❌ 错误：手动从 queue 计算（不考虑 shuffle）
final nextTrack = queue[currentIndex + 1];
```

### 5. PlaybackContext 和播放锁（2026-01-19 重构）

**问题**：快速连续点击多首歌曲时，会加载所有点击过的歌曲而不是只加载最后一个，导致根据加载速度轮流播放。同时可能出现：
- `Player already exists` 错误（just_audio_media_kit）
- `isLoading` 状态卡住不重置
- 进度条不立即重置，仍显示旧歌曲进度
- 点击播放按钮会继续播放旧歌曲

**解决方案**：`_PlaybackContext` 统一管理 + 请求 ID 机制 + 锁包装类

```dart
/// 播放模式
enum PlayMode {
  queue,      // 正常队列播放
  temporary,  // 临时播放（播放完成后恢复）
  detached,   // 脱离队列（如队列清空后继续播放）
}

/// 播放上下文 - 统一管理所有播放相关状态
class _PlaybackContext {
  final PlayMode mode;
  final int activeRequestId;     // 当前活动的请求 ID（0 表示无活动请求）
  final int? savedQueueIndex;    // 临时播放保存的队列索引
  final Duration? savedPosition; // 临时播放保存的播放位置
  final bool? savedWasPlaying;   // 临时播放保存的播放状态
  
  bool get isTemporary => mode == PlayMode.temporary;
  bool get isInLoadingState => activeRequestId > 0;
  bool get hasSavedState => savedQueueIndex != null;
  
  _PlaybackContext copyWith({...});
}

/// 带有请求 ID 的锁包装类
class _LockWithId {
  final int requestId;
  final Completer<void> completer;

  _LockWithId(this.requestId) : completer = Completer<void>();

  void completeIf(int expectedRequestId) {
    if (requestId == expectedRequestId && !completer.isCompleted) {
      completer.complete();
    }
  }
}

class AudioController {
  _LockWithId? _playLock;
  int _playRequestId = 0;
  _PlaybackContext _context = const _PlaybackContext();  // 统一状态管理
}
```

**统一播放入口 `_executePlayRequest()`：**
```dart
Future<void> _executePlayRequest({
  required Track track,
  required PlayMode mode,
  bool persist = true,
  bool recordHistory = true,
  bool prefetchNext = true,
}) async {
  // 1. 立即更新 UI
  _updatePlayingTrack(track);
  _updateQueueState();
  
  // 2. 进入加载状态
  _enterLoadingState();
  await _audioService.stop();
  
  final requestId = ++_playRequestId;
  _context = _context.copyWith(mode: mode, activeRequestId: requestId);
  
  // 3. 锁机制处理并发
  final existingLock = _playLock;
  final newLock = _LockWithId(requestId);
  _playLock = newLock;
  existingLock?.completeIf(existingLock.requestId);
  
  // 4. 获取 URL 并播放
  // ... URL 获取逻辑 ...
  
  // 5. 检查是否被取代
  if (_isSuperseded(requestId)) {
    newLock.completeIf(requestId);
    return;
  }
  
  // 6. 完成时退出加载状态
  _exitLoadingState(requestId);
}
```

**辅助方法：**
```dart
void _enterLoadingState() {
  state = state.copyWith(isLoading: true, position: Duration.zero, error: null);
}

void _exitLoadingState(int requestId) {
  if (_context.activeRequestId == requestId) {
    _context = _context.copyWith(activeRequestId: 0);
    state = state.copyWith(isLoading: false);
  }
}

bool _isSuperseded(int requestId) => _playRequestId != requestId;
```

**播放器状态事件处理** - 使用 `_context.isInLoadingState` 防止覆盖：
```dart
void _onPlayerStateChanged(just_audio.PlayerState playerState) {
  state = state.copyWith(
    isPlaying: playerState.playing,
    isBuffering: playerState.processingState == just_audio.ProcessingState.buffering,
    // 防止播放器事件覆盖 URL 获取期间的状态
    isLoading: _context.isInLoadingState || 
               playerState.processingState == just_audio.ProcessingState.loading,
    processingState: playerState.processingState,
  );
}

void _onPositionChanged(Duration position) {
  // 加载期间忽略位置更新（防止旧歌曲位置覆盖已重置的进度条）
  if (_context.isInLoadingState) return;
  
  state = state.copyWith(position: position);
  // ...
}
```

**AudioService 修复** - 等待播放器 idle 状态：
```dart
// playUrl/playFile 中
await _player.stop();

// 等待播放器进入 idle 状态，确保底层播放器完全清理
if (_player.processingState != ProcessingState.idle) {
  try {
    await _player.playerStateStream
        .where((state) => state.processingState == ProcessingState.idle)
        .first
        .timeout(const Duration(milliseconds: 500));
  } catch (e) {
    // 超时也继续
  }
}

await _player.setAudioSource(audioSource);
```

### 6. Mix 播放模式（YouTube Mix/Radio）

**用途：** 播放 YouTube Mix/Radio 播放列表（ID 以 "RD" 開頭），這是動態生成的無限播放列表。

**新增 PlayMode：**
```dart
enum PlayMode {
  queue,      // 正常队列播放
  temporary,  // 临时播放
  detached,   // 脱离队列
  mix,        // Mix 播放模式（新增）
}
```

**_MixPlaylistState（AudioController 內部）：**
```dart
class _MixPlaylistState {
  final String playlistId;     // RDxxxxxx
  final String seedVideoId;    // 種子視頻 ID
  final String title;          // 歌單標題
  final Set<String> seenVideoIds = {};  // 去重用
  bool isLoadingMore = false;
}
```

**持久化（跨 App 重啟保留）：**
```dart
// PlayQueue 新增欄位
bool isMixMode = false;
String? mixPlaylistId;
String? mixSeedVideoId;
String? mixTitle;

// QueueManager 新增方法
Future<void> setMixMode({required bool enabled, String? playlistId, String? seedVideoId, String? title});
Future<void> clearMixMode();
```

**初始化時恢復：**
```dart
// AudioController.initialize()
if (_queueManager.isMixMode) {
  _mixState = _MixPlaylistState(
    playlistId: _queueManager.mixPlaylistId!,
    seedVideoId: _queueManager.mixSeedVideoId!,
    title: _queueManager.mixTitle!,
  );
  _mixState!.addSeenVideoIds(_queueManager.tracks.map((t) => t.sourceId));
  _context = _context.copyWith(mode: PlayMode.mix);
  state = state.copyWith(isMixMode: true, mixTitle: _queueManager.mixTitle);
}
```

**關鍵行為：**
- **禁止 shuffle** - 按鈕禁用（灰色），tooltip 顯示 "Mix 模式不支持隨機播放"
- **禁止 addToQueue/addNext** - 返回 `false`，顯示 Toast "Mix 播放列表不支持添加歌曲"
- **自動加載更多** - 播放到最後 1-2 首時自動調用 `_loadMoreMixTracks()`
- **退出 Mix 模式** - `clearQueue()` 或播放其他歌單時自動退出

**UI 變更：**
- 隊列頁標題：`Mix · {歌單名稱}`（使用 60% 可用寬度，超長截斷）
- 歌單詳情頁：Mix 歌單的歌曲隱藏整個 PopupMenu（不顯示下載/添加等選項）
- 播放器頁面：shuffle 按鈕禁用

### 7. 记住播放位置（Remember Playback Position）
**用途：** 长视频/音频自动记住播放位置，下次播放时从上次位置继续

**触发条件：**
- 视频时长 > 10 分钟
- 且播放进度 > 5%

**相关方法：**
```dart
// QueueManager
Future<void> rememberPlaybackPosition(Track track, Duration position);
Future<Duration?> getRememberedPosition(Track track);
Future<void> clearRememberedPosition(Track track);
```

**存储：** 使用 Isar 数据库，`Track.rememberedPositionMs` 字段

**播放时恢复：**
- `_playTrack()` 内部会调用 `_queueManager.getRememberedPosition()`
- 如果有记住的位置，自动 seek 到该位置

## Provider 结构

```dart
// 主要使用这个
final audioControllerProvider = StateNotifierProvider<AudioController, PlayerState>

// 内部依赖（UI 不应直接使用）
final audioServiceProvider = Provider<AudioService>
final queueManagerProvider = Provider<QueueManager>

// 便捷 Provider（从 audioControllerProvider 派生）
final isPlayingProvider
final currentTrackProvider
final positionProvider
final durationProvider
final queueProvider
final isShuffleEnabledProvider
final loopModeProvider
```

## Android 后台播放

**使用 `audio_service` 包实现后台播放和通知栏控制**

> 注意：项目已从 `just_audio_background` 迁移到 `audio_service`，后者提供更灵活的控制。

### 初始化（main.dart）

```dart
import 'package:audio_service/audio_service.dart';
import 'services/audio/audio_handler.dart';

/// 全局 AudioHandler 实例，供 AudioController 使用
late FmpAudioHandler audioHandler;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Android/iOS 后台播放初始化
  if (Platform.isAndroid || Platform.isIOS) {
    audioHandler = await AudioService.init(
      builder: () => FmpAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.personal.fmp.channel.audio',
        androidNotificationChannelName: 'FMP 音频播放',
        androidNotificationChannelDescription: 'FMP 音乐播放器后台播放通知',
        androidNotificationOngoing: true,
        androidShowNotificationBadge: true,
        androidStopForegroundOnPause: true,
        fastForwardInterval: Duration(seconds: 10),
        rewindInterval: Duration(seconds: 10),
      ),
    );
  } else {
    // 桌面平台创建 dummy handler 保持代码一致性
    audioHandler = FmpAudioHandler();
  }
  // ...
}
```

### FmpAudioHandler（lib/services/audio/audio_handler.dart）

自定义 AudioHandler，处理媒体通知和控制按钮：

```dart
class FmpAudioHandler extends BaseAudioHandler with SeekHandler {
  // 回调函数，由 AudioController 设置
  Future<void> Function()? onPlay;
  Future<void> Function()? onPause;
  Future<void> Function()? onStop;
  Future<void> Function()? onSkipToNext;
  Future<void> Function()? onSkipToPrevious;
  Future<void> Function(Duration position)? onSeek;
  Future<void> Function(AudioServiceRepeatMode mode)? onSetRepeatMode;
  Future<void> Function(AudioServiceShuffleMode mode)? onSetShuffleMode;

  /// 更新当前播放的媒体项
  void updateCurrentMediaItem(Track track) {
    final item = MediaItem(
      id: track.uniqueKey,
      title: track.title,
      artist: track.artist ?? '未知艺术家',
      artUri: track.thumbnailUrl != null ? Uri.parse(track.thumbnailUrl!) : null,
      duration: track.durationMs != null ? Duration(milliseconds: track.durationMs!) : null,
    );
    mediaItem.add(item);
  }

  /// 更新播放状态（位置、缓冲、播放中等）
  void updatePlaybackState({...});
  
  /// 更新循环模式
  void updateRepeatMode(LoopMode loopMode);
  
  /// 更新随机播放模式
  void updateShuffleMode(bool isShuffleEnabled);

  // AudioHandler 回调方法 - 委托给 AudioController
  @override
  Future<void> play() async => await onPlay?.call();
  @override
  Future<void> pause() async => await onPause?.call();
  @override
  Future<void> skipToNext() async => await onSkipToNext?.call();
  @override
  Future<void> skipToPrevious() async => await onSkipToPrevious?.call();
  // ...
}
```

### AudioController 集成

```dart
class AudioController extends StateNotifier<PlayerState> {
  final FmpAudioHandler _audioHandler;

  /// 设置 AudioHandler 回调
  void _setupAudioHandler() {
    _audioHandler.onPlay = play;
    _audioHandler.onPause = pause;
    _audioHandler.onStop = stop;
    _audioHandler.onSkipToNext = next;
    _audioHandler.onSkipToPrevious = previous;
    _audioHandler.onSeek = seekTo;
    // ...
  }

  /// 播放时更新媒体通知
  Future<void> _playTrack(Track track, String url, {...}) async {
    // ... 播放逻辑
    _audioHandler.updateCurrentMediaItem(track);
  }

  /// 状态变化时同步到通知
  void _onPlayerStateChanged(PlayerState state) {
    _audioHandler.updatePlaybackState(
      isPlaying: state.isPlaying,
      position: state.position,
      // ...
    );
  }
}
```

### AndroidManifest.xml 必需配置

- `WAKE_LOCK` 权限
- `FOREGROUND_SERVICE` 权限
- `FOREGROUND_SERVICE_MEDIA_PLAYBACK` 权限（SDK 34+）
- `AudioServiceActivity` 作为主 Activity
- `AudioService` 服务声明
- `MediaButtonReceiver` 接收器

## Windows 平台后端

### 媒体键和 SMTC 支持

**使用 `smtc_windows` 包实现 Windows 系统媒体传输控制 (SMTC)**

> 注意：`smtc_windows` 需要 Rust 环境，请确保已安装 rustup

**初始化（main.dart）：**
```dart
import 'package:smtc_windows/smtc_windows.dart';
import 'services/audio/windows_smtc_handler.dart';

late WindowsSmtcHandler windowsSmtcHandler;

void main() async {
  // ... 其他初始化

  // Windows 平台初始化 SMTC
  if (Platform.isWindows) {
    await SMTCWindows.initialize();
    windowsSmtcHandler = WindowsSmtcHandler();
    await windowsSmtcHandler.initialize();
  } else {
    windowsSmtcHandler = WindowsSmtcHandler();
  }
}
```

**WindowsSmtcHandler（lib/services/audio/windows_smtc_handler.dart）：**
- 处理媒体键事件（播放/暂停/上一曲/下一曲/停止）
- 更新媒体元数据（标题、艺术家、封面）
- 更新播放状态和时间线
- 与 AudioController 通过回调函数连接

**AudioController 集成：**
- `_setupWindowsSmtc()` 设置回调函数
- `_updatePlayingTrack()` 同步更新媒体信息
- `_onPlayerStateChanged()` / `_onPositionChanged()` 同步更新播放状态

### 音频后端

**直接使用 `media_kit`（不通过 `just_audio`）**

之前的 `just_audio` + `just_audio_media_kit` 方案已被替换。原因：
- `just_audio_media_kit` 在传递 headers 时创建本地 HTTP 代理
- 该代理对所有 audio-only 流都有问题，只有 muxed 流能工作

**现在的方案：**
- `media_kit` 原生支持 `httpHeaders`（通过 `Media(url, httpHeaders: headers)`）
- 无需代理，所有流类型都能正常工作
- YouTube 播放现在优先使用 audio-only 流（带宽更低）

**自定义类型** (`audio_types.dart`):
- `FmpAudioProcessingState` - 替代 `just_audio.ProcessingState`
- `MediaKitPlayerState` - 从 media_kit 事件合成

**音量转换**：media_kit 使用 0-100 范围，应用使用 0-1 范围。转换在 `MediaKitAudioService` 中处理。

**YouTube 流优先级（2026-02 更新）**：
1. **Audio-only via androidVr client** - 优先使用（带宽最低，无视频数据）
2. **Muxed**（视频+音频）- androidVr 失败时的后备
3. **HLS**（m3u8 分段）- 最后备选

**重要发现（2026-02）**：只有 `YoutubeApiClient.androidVr` 客户端产生的 audio-only 流 URL 可以正常访问。其他客户端（`android`, `ios`, `safari`）的 audio-only 流返回 HTTP 403。androidVr 客户端的 URL 包含 `c=ANDROID_VR` 参数。

**带宽对比**：
- Audio-only (mp4/aac): ~128-256 kbps
- Muxed (360p video+audio): ~500-1000 kbps

**实现**：`YouTubeSource.getAudioUrl()` 优先尝试 androidVr 客户端获取 audio-only 流，失败则回退到 muxed 流。

## 进度条拖动最佳实践

**问题：** 如果 Slider 的 `onChanged` 直接调用 `seekToProgress()`，连续拖动会产生大量 seek 请求，
可能导致消息队列溢出或性能问题。

**正确实现：** 只在拖动结束时才触发 seek

```dart
// 状态
bool _isDragging = false;
double _dragProgress = 0.0;

// Slider 实现
Slider(
  value: _isDragging ? _dragProgress : state.progress.clamp(0.0, 1.0),
  onChangeStart: (value) {
    setState(() {
      _isDragging = true;
      _dragProgress = value;
    });
  },
  onChanged: (value) {
    // 只更新本地状态，不触发 seek
    setState(() => _dragProgress = value);
  },
  onChangeEnd: (value) {
    // 只在这里触发 seek
    controller.seekToProgress(value);
    setState(() => _isDragging = false);
  },
)
```

**注意：** `mini_player.dart` 和 `player_page.dart` 都已正确实现此模式。

## 常见错误及避免方法

### ❌ 错误：在播放操作之后才更新 playingTrack
```dart
// 错误！播放操作会触发状态事件，导致 UI 在 playingTrack 更新前重建
await _audioService.playUrl(url, ...);
_updatePlayingTrack(track);  // 太晚了！
```

### ✅ 正确：先更新 playingTrack 再播放
```dart
// 正确！在播放操作之前更新，避免 Android 上 UI 刷新延迟
_updatePlayingTrack(track);
await _audioService.playUrl(url, ...);
```

**原因**：`playUrl/playFile` 内部会触发 `playerStateStream` 事件，导致 `_onPlayerStateChanged` 被调用并更新 state。如果 `playingTrack` 还没更新，UI 会显示旧的歌曲信息。在 Android 上这个问题更明显（事件处理时机与 Windows 不同）。



### ❌ 错误：UI 直接调用 setVolume 进行静音
```dart
// 错误！不会记住原音量
controller.setVolume(0);
controller.setVolume(1.0);
```

### ✅ 正确：使用 toggleMute
```dart
controller.toggleMute();
```

### ❌ 错误：在 AudioService 添加业务逻辑
AudioService 应该保持简单，只封装 just_audio。

### ✅ 正确：业务逻辑放在 AudioController
队列管理、状态持久化、临时播放等逻辑都在 AudioController。

### ❌ 错误：UI 直接使用 AudioService
```dart
ref.read(audioServiceProvider).play();  // 错误
```

### ✅ 正确：UI 通过 AudioController
```dart
ref.read(audioControllerProvider.notifier).play();
```

## 音频会话处理（AudioService）

```dart
// Duck 模式（如来电时降低音量）
_volumeBeforeDuck = _player.volume;
_player.setVolume(_player.volume * 0.5);

// Duck 结束后恢复
_player.setVolume(_volumeBeforeDuck);

// 耳机拔出自动暂停
session.becomingNoisyEventStream.listen((_) {
  _player.pause();
});
```

## 文件位置

| 文件 | 职责 |
|------|------|
| `lib/services/audio/media_kit_audio_service.dart` | 底层播放控制（media_kit） |
| `lib/services/audio/audio_types.dart` | 自定义类型（FmpAudioProcessingState 等） |
| `lib/services/audio/audio_provider.dart` | AudioController + PlayerState + Providers |
| `lib/services/audio/queue_manager.dart` | 队列管理 |
| `lib/ui/pages/player/player_page.dart` | 全屏播放器页面 |
| `lib/ui/widgets/player/mini_player.dart` | 底部迷你播放器 |
| `lib/ui/pages/queue/queue_page.dart` | 队列页面 |
