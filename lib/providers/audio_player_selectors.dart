import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/settings.dart';
import '../services/audio/audio_provider.dart';
import '../services/audio/audio_types.dart';

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
          audioDevices.map((device) => Object.hash(device.name, device.description)),
        ),
        currentAudioDevice == null
            ? null
            : Object.hash(
                currentAudioDevice!.name,
                currentAudioDevice!.description,
              ),
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

  bool get hasAnyInfo => bitrate != null || container != null || codec != null || streamType != null;

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

final desktopAudioDeviceStateProvider = Provider<DesktopAudioDeviceState>((ref) {
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
