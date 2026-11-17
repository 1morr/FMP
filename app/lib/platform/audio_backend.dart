import 'dart:io';

import 'package:fmp/core/log/log.dart';
import 'package:fmp/playback/audio_backend.dart';
import 'package:fmp/playback/backends/hls/hls_packager.dart';
import 'package:fmp/playback/backends/just_audio_backend.dart';
import 'package:fmp/playback/backends/media_kit_backend.dart';

/// 依平台挑音訊後端（brief〈播放〉、事實 K1）：Windows 用 media_kit，其他平台
/// 用 just_audio。依賴規則只准 `platform/` 判斷平台（architecture〈依賴規則〉）。
///
/// Apple 平台的 just_audio（AVPlayer）把單檔 fragmented MP4 包成 HLS 播
/// （ADR 0040）；包不了時寫一筆 warning，照舊直接播。[fetchRange] 換掉抓索引
/// 的方式，給測試用。
AudioBackend createAudioBackend(Log log, {FetchRange? fetchRange}) {
  if (Platform.isWindows) return MediaKitBackend();
  if (!Platform.isIOS && !Platform.isMacOS) return JustAudioBackend();
  return JustAudioBackend(
    hls: HlsPackager(fetchRange: fetchRange),
    onHlsUnavailable: (reason) =>
        log.warning('Playing the stream without HLS: ${reason.reason}'),
  );
}
