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
│      AudioService       │    │       QueueManager          │
│   (audio_service.dart)  │    │    (queue_manager.dart)     │
│                         │    │                             │
│ 职责：                   │    │ 职责：                       │
│ - 封装 just_audio       │    │ - 管理播放队列               │
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
│ - 队列逻辑              │    │ - prefetchNext              │
└─────────────────────────┘    └─────────────────────────────┘
           │                              │
           ▼                              ▼
┌─────────────────────────┐    ┌─────────────────────────────┐
│       just_audio        │    │      Isar Database          │
│    (AudioPlayer)        │    │   (QueueRepository, etc.)   │
│           │             │    └─────────────────────────────┘
│           ▼             │
│  just_audio_media_kit   │
│    (Windows/Linux)      │
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

### 0.1 "脱离队列"状态检测
当 `playingTrack` 与 `queueTrack` 不一致时，称为"脱离队列"状态。发生场景：
1. **临时播放模式** - `_isTemporaryPlay = true`
2. **清空队列后继续播放** - 队列被清空但歌曲继续播放，之后添加新歌曲
3. **其他不一致情况** - `_playingTrack.id != queueTrack.id`

**行为：**
- `upcomingTracks` 显示队列从索引 0 开始的歌曲
- 点击"下一首"/"上一首"会播放队列的第一首
- `canPlayNext`/`canPlayPrevious` 只要队列不为空就为 true

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

### 2. 临时播放功能
**用途：** 搜索页/歌单页点击歌曲时，临时播放该歌曲，播放完成后恢复原队列位置

**相关字段：**
```dart
bool _isTemporaryPlay = false;
List<Track>? _savedQueue;
int? _savedIndex;
Duration? _savedPosition;
bool _savedIsPlaying = false;
```

**流程：**
1. `playTemporary(track)` - 保存当前状态，播放临时歌曲
2. 歌曲完成时 `_onTrackCompleted` 检测到 `_isTemporaryPlay`
3. `_restoreSavedState()` - 恢复队列，回退10秒，如果之前在播放则继续播放

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

### 5. 播放锁（防止竞态）
```dart
Completer<void>? _playLock;
int _playRequestId = 0;
```
用于防止快速切歌时的竞态条件，确保只有最新的播放请求会执行。

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

**使用 `just_audio_media_kit` 而非 `just_audio_windows`**

`just_audio_windows` 存在已知的平台线程问题（[GitHub Issue #30](https://github.com/bdlukaa/just_audio_windows/issues/30)），
在长视频 seek 操作时会导致 "Failed to post message to main thread" 错误和应用卡死。

**解决方案：**
```yaml
# pubspec.yaml
dependencies:
  just_audio: ^0.9.43
  just_audio_media_kit: ^2.1.0      # 替代 just_audio_windows
  media_kit_libs_windows_audio: any  # media_kit 的 Windows 音频库
```

```dart
// main.dart
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  JustAudioMediaKit.ensureInitialized();  // 必须在使用音频前调用
  // ...
}
```

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
| `lib/services/audio/audio_service.dart` | 底层播放控制 |
| `lib/services/audio/audio_provider.dart` | AudioController + PlayerState + Providers |
| `lib/services/audio/queue_manager.dart` | 队列管理 |
| `lib/ui/pages/player/player_page.dart` | 全屏播放器页面 |
| `lib/ui/widgets/player/mini_player.dart` | 底部迷你播放器 |
| `lib/ui/pages/queue/queue_page.dart` | 队列页面 |
