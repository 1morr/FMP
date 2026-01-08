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
└─────────────────────────┘    └─────────────────────────────┘
```

## 重要设计决策

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

## 常见错误及避免方法

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
