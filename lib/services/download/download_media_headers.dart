import '../../data/models/track.dart';
import '../audio/audio_stream_manager.dart';

Map<String, String> buildDownloadMediaHeaders(
  SourceType sourceType, {
  Map<String, String>? authHeaders,
}) {
  final headers = switch (sourceType) {
    SourceType.bilibili => <String, String>{
        'Referer': 'https://www.bilibili.com',
        'User-Agent': AudioStreamManager.defaultPlaybackUserAgent,
      },
    SourceType.youtube => <String, String>{
        'Origin': 'https://www.youtube.com',
        'Referer': 'https://www.youtube.com/',
        'User-Agent': AudioStreamManager.defaultPlaybackUserAgent,
      },
    SourceType.netease => <String, String>{
        'Origin': 'https://music.163.com',
        'Referer': 'https://music.163.com/',
        'User-Agent': AudioStreamManager.defaultPlaybackUserAgent,
      },
  };

  if (sourceType == SourceType.netease && authHeaders != null) {
    for (final key in const ['Cookie', 'Origin', 'Referer', 'User-Agent']) {
      final value = authHeaders[key];
      if (value != null && value.isNotEmpty) {
        headers[key] = value;
      }
    }
  }

  return headers;
}
