import 'dart:io';

import 'package:fmp/playback/audio_backend.dart';
import 'package:fmp/playback/backends/just_audio_backend.dart';
import 'package:fmp/playback/backends/media_kit_backend.dart';

/// 依平台挑音訊後端（brief〈播放〉、事實 K1）：Windows 用 media_kit，其他平台
/// 用 just_audio。依賴規則只准 `platform/` 判斷平台（plan〈依賴規則〉）。
AudioBackend createAudioBackend() =>
    Platform.isWindows ? MediaKitBackend() : JustAudioBackend();
