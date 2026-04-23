import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AudioRuntimePlatform { mobile, desktop }

AudioRuntimePlatform selectAudioRuntimePlatform(String platform) {
  switch (platform.toLowerCase()) {
    case 'android':
    case 'ios':
      return AudioRuntimePlatform.mobile;
    case 'windows':
    case 'linux':
    case 'macos':
      return AudioRuntimePlatform.desktop;
    default:
      return AudioRuntimePlatform.desktop;
  }
}

AudioRuntimePlatform detectAudioRuntimePlatform() {
  return selectAudioRuntimePlatform(Platform.operatingSystem);
}

final audioRuntimePlatformProvider = Provider<AudioRuntimePlatform>((ref) {
  return detectAudioRuntimePlatform();
});
