import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/data/models/play_queue.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/services/audio/audio_types.dart';
import 'package:fmp/services/audio/queue_state.dart';
import 'package:fmp/providers/audio/audio_controller_provider.dart';

@immutable
class DesktopAudioDeviceState {
  const DesktopAudioDeviceState({
    required this.audioDevices,
    required this.currentAudioDevice,
  });

  final List<FmpAudioDevice> audioDevices;
  final FmpAudioDevice? currentAudioDevice;

  bool get hasSelectableDevices => audioDevices.length > 1;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is DesktopAudioDeviceState &&
            _sameAudioDeviceList(audioDevices, other.audioDevices) &&
            _sameAudioDevice(currentAudioDevice, other.currentAudioDevice);
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(
      audioDevices.map(
        (device) => Object.hash(device.name, device.description),
      ),
    ),
    currentAudioDevice == null
        ? null
        : Object.hash(
            currentAudioDevice!.name,
            currentAudioDevice!.description,
          ),
  );
}

/// 播放控制列需要的佇列面向狀態。
@immutable
class QueueControlState {
  const QueueControlState({
    required this.isShuffleEnabled,
    required this.loopMode,
    required this.isMixMode,
    required this.canPlayPrevious,
    required this.canPlayNext,
  });

  final bool isShuffleEnabled;
  final LoopMode loopMode;
  final bool isMixMode;
  final bool canPlayPrevious;
  final bool canPlayNext;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is QueueControlState &&
            isShuffleEnabled == other.isShuffleEnabled &&
            loopMode == other.loopMode &&
            isMixMode == other.isMixMode &&
            canPlayPrevious == other.canPlayPrevious &&
            canPlayNext == other.canPlayNext;
  }

  @override
  int get hashCode => Object.hash(
    isShuffleEnabled,
    loopMode,
    isMixMode,
    canPlayPrevious,
    canPlayNext,
  );
}

@immutable
class CurrentStreamMetadata {
  const CurrentStreamMetadata({
    required this.bitrate,
    required this.container,
    required this.codec,
    required this.streamType,
  });

  final int? bitrate;
  final String? container;
  final String? codec;
  final StreamType? streamType;

  bool get hasAnyInfo =>
      bitrate != null ||
      container != null ||
      codec != null ||
      streamType != null;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CurrentStreamMetadata &&
            bitrate == other.bitrate &&
            container == other.container &&
            codec == other.codec &&
            streamType == other.streamType;
  }

  @override
  int get hashCode => Object.hash(bitrate, container, codec, streamType);
}

final playbackSpeedProvider = Provider<double>((ref) {
  return ref.watch(audioControllerProvider.select((state) => state.speed));
});

final desktopAudioDeviceStateProvider = Provider<DesktopAudioDeviceState>((
  ref,
) {
  return ref.watch(
    audioControllerProvider.select(
      (state) => DesktopAudioDeviceState(
        audioDevices: state.audioDevices,
        currentAudioDevice: state.currentAudioDevice,
      ),
    ),
  );
});

final currentStreamMetadataProvider = Provider<CurrentStreamMetadata>((ref) {
  return ref.watch(
    audioControllerProvider.select(
      (state) => CurrentStreamMetadata(
        bitrate: state.currentBitrate,
        container: state.currentContainer,
        codec: state.currentCodec,
        streamType: state.currentStreamType,
      ),
    ),
  );
});

bool _sameAudioDevice(FmpAudioDevice? a, FmpAudioDevice? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  return a.name == b.name && a.description == b.description;
}

bool _sameAudioDeviceList(List<FmpAudioDevice> a, List<FmpAudioDevice> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;

  for (var i = 0; i < a.length; i++) {
    if (!_sameAudioDevice(a[i], b[i])) {
      return false;
    }
  }

  return true;
}

/// 当前播放状态
final isPlayingProvider = Provider<bool>((ref) {
  return ref.watch(audioControllerProvider).isPlaying;
});

/// 当前歌曲
final currentTrackProvider = Provider<Track?>((ref) {
  return ref.watch(audioControllerProvider.select((s) => s.currentTrack));
});

/// 当前进度
final positionProvider = Provider<Duration>((ref) {
  return ref.watch(audioControllerProvider.select((s) => s.position));
});

/// 总时长
final durationProvider = Provider<Duration?>((ref) {
  return ref.watch(audioControllerProvider.select((s) => s.duration));
});

/// 播放队列
final queueProvider = Provider<List<Track>>((ref) {
  return ref.watch(queueStateProvider.select((s) => s.queue));
});

final queueVersionProvider = Provider<int>((ref) {
  return ref.watch(queueStateProvider.select((s) => s.queueVersion));
});

final queueTrackProvider = Provider<Track?>((ref) {
  return ref.watch(queueStateProvider.select((s) => s.queueTrack));
});

/// 是否啟用隨機播放
final isShuffleEnabledProvider = Provider<bool>((ref) {
  return ref.watch(queueStateProvider.select((s) => s.isShuffleEnabled));
});

/// 迴圈模式
final loopModeProvider = Provider<LoopMode>((ref) {
  return ref.watch(queueStateProvider.select((s) => s.loopMode));
});

/// 接下來要播的曲目
final upcomingTracksProvider = Provider<List<Track>>((ref) {
  return ref.watch(queueStateProvider.select((s) => s.upcomingTracks));
});

/// 佇列導覽能力與 Mix 身分，播放控制列一次讀完。
final queueControlStateProvider = Provider<QueueControlState>((ref) {
  return ref.watch(
    queueStateProvider.select(
      (s) => QueueControlState(
        isShuffleEnabled: s.isShuffleEnabled,
        loopMode: s.loopMode,
        isMixMode: s.isMixMode,
        canPlayPrevious: s.canPlayPrevious,
        canPlayNext: s.canPlayNext,
      ),
    ),
  );
});
