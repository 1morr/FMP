import 'package:fmp/core/logging/log.dart';
import 'package:fmp/platform/audio/audio.dart';
import 'package:fmp/playback/backends/audio_backend.dart';
import 'package:fmp/playback/backends/just_audio_backend.dart';
import 'package:fmp/playback/backends/media_kit_backend.dart';

/// 依平台宣告的 [kind] 建立後端。只有這裡與兩個實作檔知道具體的引擎。
AudioBackend createAudioBackend(AudioBackendKind kind, {required Log log}) =>
    switch (kind) {
      AudioBackendKind.justAudio => JustAudioBackend(log: log),
      AudioBackendKind.mediaKit => MediaKitBackend.create(log: log),
    };
