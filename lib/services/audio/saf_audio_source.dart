import 'dart:async';
import 'package:just_audio/just_audio.dart';
import '../saf/saf_service.dart';

/// SAF 音频源
/// 
/// 用于播放 content:// URI 的音频文件
/// 通过 Platform Channel 实现 range request
class SafAudioSource extends StreamAudioSource {
  final String contentUri;
  final int fileSize;
  final SafService _safService;
  
  SafAudioSource._({
    required this.contentUri,
    required this.fileSize,
    required SafService safService,
    super.tag,
  }) : _safService = safService;
  
  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= fileSize;
    
    final length = end - start;
    
    // 读取指定范围的数据
    final bytes = await _safService.readRange(contentUri, start, length);
    
    return StreamAudioResponse(
      sourceLength: fileSize,
      contentLength: length,
      offset: start,
      stream: Stream.value(bytes),
      contentType: 'audio/mp4', // m4a 格式
    );
  }
  
  /// 创建 SafAudioSource（需要先获取文件大小）
  /// 
  /// [contentUri] content:// URI
  /// [safService] SAF 服务实例
  /// [tag] 可选的 MediaItem 元数据（用于后台播放通知）
  static Future<SafAudioSource> create(
    String contentUri,
    SafService safService, {
    dynamic tag,
  }) async {
    final fileSize = await safService.getFileSize(contentUri);
    return SafAudioSource._(
      contentUri: contentUri,
      fileSize: fileSize,
      safService: safService,
      tag: tag,
    );
  }
}
