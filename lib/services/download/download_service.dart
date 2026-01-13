import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';
import '../../data/models/download_task.dart';
import '../../data/models/playlist_download_task.dart';
import '../../data/models/track.dart';
import '../../data/models/playlist.dart';
import '../../data/models/settings.dart';
import '../../data/models/video_detail.dart';
import '../../data/repositories/download_repository.dart';
import '../../data/repositories/track_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/sources/source_provider.dart';
import '../../data/sources/bilibili_source.dart';

/// 下载服务
class DownloadService with Logging {
  final DownloadRepository _downloadRepository;
  final TrackRepository _trackRepository;
  final SettingsRepository _settingsRepository;
  final SourceManager _sourceManager;
  
  final Dio _dio;
  
  /// 正在进行的下载任务
  final Map<int, CancelToken> _activeCancelTokens = {};
  
  /// 下载进度流控制器
  final _progressController = StreamController<DownloadProgressEvent>.broadcast();
  
  /// 下载进度流
  Stream<DownloadProgressEvent> get progressStream => _progressController.stream;
  
  /// 当前活跃的下载数量
  int _activeDownloads = 0;
  
  /// 调度器定时器（保留用于周期检查，但主要使用事件驱动）
  Timer? _schedulerTimer;
  
  /// 是否正在调度
  bool _isScheduling = false;
  
  /// 调度触发控制器（事件驱动）
  final _scheduleController = StreamController<void>.broadcast();
  
  /// 调度流订阅
  StreamSubscription<void>? _scheduleSubscription;

  DownloadService({
    required DownloadRepository downloadRepository,
    required TrackRepository trackRepository,
    required SettingsRepository settingsRepository,
    required SourceManager sourceManager,
  })  : _downloadRepository = downloadRepository,
        _trackRepository = trackRepository,
        _settingsRepository = settingsRepository,
        _sourceManager = sourceManager,
        _dio = Dio(BaseOptions(
          connectTimeout: AppConstants.downloadConnectTimeout,
          receiveTimeout: const Duration(minutes: 30),
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Referer': 'https://www.bilibili.com',
          },
        ));

  /// 初始化服务
  Future<void> initialize() async {
    logDebug('Initializing DownloadService');
    
    // 重置所有 downloading 状态的任务为 paused
    await _downloadRepository.resetDownloadingToPaused();
    
    // 启动调度器
    _startScheduler();
    
    logDebug('DownloadService initialized');
  }

  /// 释放资源
  void dispose() {
    _schedulerTimer?.cancel();
    _scheduleSubscription?.cancel();
    _scheduleController.close();
    _progressController.close();
    
    // 取消所有进行中的下载
    for (final cancelToken in _activeCancelTokens.values) {
      cancelToken.cancel('Service disposed');
    }
    _activeCancelTokens.clear();
  }

  /// 启动调度器（事件驱动 + 周期检查）
  void _startScheduler() {
    // 事件驱动：监听调度请求
    _scheduleSubscription?.cancel();
    _scheduleSubscription = _scheduleController.stream.listen((_) {
      _scheduleDownloads();
    });
    
    // 周期检查：作为备份机制，间隔加长到5秒
    _schedulerTimer?.cancel();
    _schedulerTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _scheduleDownloads();
    });
  }
  
  /// 触发调度（事件驱动入口）
  void _triggerSchedule() {
    _scheduleController.add(null);
  }

  /// 调度下载任务
  Future<void> _scheduleDownloads() async {
    if (_isScheduling) return;
    _isScheduling = true;
    
    try {
      final settings = await _settingsRepository.get();
      final maxConcurrent = settings.maxConcurrentDownloads;
      
      // 获取可用的下载槽位数
      final availableSlots = maxConcurrent - _activeDownloads;
      if (availableSlots <= 0) return;
      
      // 获取待下载的任务
      final pendingTasks = await _downloadRepository.getTasksByStatus(DownloadStatus.pending);
      
      // 启动下载
      for (int i = 0; i < availableSlots && i < pendingTasks.length; i++) {
        final task = pendingTasks[i];
        _startDownload(task);
      }
    } catch (e, stack) {
      logError('Error scheduling downloads: $e', e, stack);
    } finally {
      _isScheduling = false;
    }
  }

  /// 添加单曲下载任务
  /// [order] 在歌单中的顺序位置（从0开始）
  Future<DownloadTask?> addTrackDownload(
    Track track, {
    Playlist? fromPlaylist,
    int? playlistDownloadTaskId,
    int? order,
  }) async {
    logDebug('Adding download task for track: ${track.title}');
    
    // 首先检查文件是否已下载（无论 DownloadTask 记录是否存在）
    // 这处理了删除并重新导入歌单导致 trackId 变化的情况
    if (track.downloadedPath != null && await File(track.downloadedPath!).exists()) {
      logDebug('Track already downloaded (file exists): ${track.title}');
      return null; // 文件已存在，无需下载
    }
    
    // 检查是否已有此歌曲的下载任务
    final existingTask = await _downloadRepository.getTaskByTrackId(track.id);
    if (existingTask != null) {
      if (existingTask.isCompleted) {
        // 任务已完成但文件不存在（已由前置检查排除存在的情况），清理记录并重新下载
        logDebug('Downloaded file missing, re-queueing: ${track.title}');
        await _downloadRepository.deleteTask(existingTask.id);
        track.downloadedPath = null;
        await _trackRepository.save(track);
      } else if (!existingTask.isFailed) {
        logDebug('Download task already exists for track: ${track.title}');
        return existingTask; // 已有任务
      } else {
        // 失败的任务，删除后重新创建
        await _downloadRepository.deleteTask(existingTask.id);
      }
    }
    
    // 创建下载任务
    final priority = await _downloadRepository.getNextPriority();
    final task = DownloadTask()
      ..trackId = track.id
      ..playlistDownloadTaskId = playlistDownloadTaskId
      ..status = DownloadStatus.pending
      ..priority = priority
      ..createdAt = DateTime.now();
    
    final savedTask = await _downloadRepository.saveTask(task);
    
    // 触发调度（事件驱动）
    _triggerSchedule();
    
    return savedTask;
  }

  /// 添加歌单下载任务
  Future<PlaylistDownloadTask?> addPlaylistDownload(Playlist playlist) async {
    logDebug('Adding playlist download task: ${playlist.name}');

    // 检查是否已有此歌单的下载任务
    final existingTask = await _downloadRepository.getPlaylistTaskByPlaylistId(playlist.id);
    if (existingTask != null) {
      // 只有正在下载中的任务不允许重复添加
      if (existingTask.status == DownloadStatus.downloading) {
        logDebug('Playlist download task is currently downloading: ${playlist.name}');
        return existingTask;
      }
      // 其他状态（pending/paused/completed/failed）都允许重新下载
      logDebug('Re-downloading playlist: ${playlist.name}');
      await _downloadRepository.deletePlaylistTask(existingTask.id);
    }

    // 获取歌单中的所有歌曲
    final tracks = await _trackRepository.getByIds(playlist.trackIds);
    if (tracks.isEmpty) {
      logDebug('Playlist has no tracks: ${playlist.name}');
      return null;
    }

    // 创建歌单下载任务
    final priority = await _downloadRepository.getNextPriority();
    final playlistTask = PlaylistDownloadTask()
      ..playlistId = playlist.id
      ..playlistName = playlist.name
      ..trackIds = playlist.trackIds
      ..status = DownloadStatus.pending
      ..priority = priority
      ..createdAt = DateTime.now();

    final savedPlaylistTask = await _downloadRepository.savePlaylistTask(playlistTask);

    // 下载歌单封面
    await _downloadPlaylistCover(playlist, savedPlaylistTask);

    // 为每个歌曲创建下载任务
    for (final track in tracks) {
      await addTrackDownload(
        track,
        fromPlaylist: playlist,
        playlistDownloadTaskId: savedPlaylistTask.id,
      );
    }

    return savedPlaylistTask;
  }

  /// 下载歌单封面到分类文件夹
  Future<void> _downloadPlaylistCover(Playlist playlist, PlaylistDownloadTask task) async {
    if (playlist.coverUrl == null || playlist.coverUrl!.isEmpty) {
      logDebug('Playlist has no cover URL: ${playlist.name}');
      return;
    }

    try {
      final settings = await _settingsRepository.get();

      // 获取基础下载目录
      String baseDir;
      if (settings.customDownloadDir != null && settings.customDownloadDir!.isNotEmpty) {
        baseDir = settings.customDownloadDir!;
      } else {
        baseDir = await _getDefaultDownloadDir();
      }

      // 歌单文件夹路径
      final subDir = _sanitizeFileName(task.playlistName);
      final playlistFolder = Directory(p.join(baseDir, subDir));

      // 确保目录存在
      if (!await playlistFolder.exists()) {
        await playlistFolder.create(recursive: true);
      }

      // 下载封面到歌单文件夹
      final coverPath = p.join(playlistFolder.path, 'playlist_cover.jpg');
      await _dio.download(playlist.coverUrl!, coverPath);
      logDebug('Downloaded playlist cover: ${playlist.name}');
    } catch (e) {
      logDebug('Failed to download playlist cover: $e');
    }
  }

  /// 暂停下载任务
  Future<void> pauseTask(int taskId) async {
    logDebug('Pausing download task: $taskId');
    
    // 取消正在进行的下载
    final cancelToken = _activeCancelTokens.remove(taskId);
    if (cancelToken != null) {
      cancelToken.cancel('User paused');
      _activeDownloads--;
    }
    
    await _downloadRepository.updateTaskStatus(taskId, DownloadStatus.paused);
  }

  /// 恢复下载任务
  Future<void> resumeTask(int taskId) async {
    logDebug('Resuming download task: $taskId');
    await _downloadRepository.updateTaskStatus(taskId, DownloadStatus.pending);
    _triggerSchedule();
  }

  /// 取消/删除下载任务
  Future<void> cancelTask(int taskId) async {
    logDebug('Canceling download task: $taskId');
    
    // 取消正在进行的下载
    final cancelToken = _activeCancelTokens.remove(taskId);
    if (cancelToken != null) {
      cancelToken.cancel('User cancelled');
      _activeDownloads--;
    }
    
    await _downloadRepository.deleteTask(taskId);
  }

  /// 重试下载任务
  Future<void> retryTask(int taskId) async {
    logDebug('Retrying download task: $taskId');
    
    final task = await _downloadRepository.getTaskById(taskId);
    if (task == null) return;
    
    task.status = DownloadStatus.pending;
    task.progress = 0.0;
    task.downloadedBytes = 0;
    task.errorMessage = null;
    
    await _downloadRepository.saveTask(task);
    _triggerSchedule();
  }

  /// 暂停所有任务
  Future<void> pauseAll() async {
    logDebug('Pausing all downloads');
    
    // 取消所有进行中的下载
    for (final entry in _activeCancelTokens.entries) {
      entry.value.cancel('User paused all');
    }
    _activeCancelTokens.clear();
    _activeDownloads = 0;
    
    await _downloadRepository.pauseAllTasks();
  }

  /// 恢复所有任务
  Future<void> resumeAll() async {
    logDebug('Resuming all downloads');
    await _downloadRepository.resumeAllTasks();
    _triggerSchedule();
  }

  /// 清空队列
  Future<void> clearQueue() async {
    logDebug('Clearing download queue');

    // 取消所有进行中的下载
    for (final entry in _activeCancelTokens.entries) {
      entry.value.cancel('Queue cleared');
    }
    _activeCancelTokens.clear();
    _activeDownloads = 0;

    await _downloadRepository.clearQueue();
  }

  /// 清除已完成的任务
  Future<void> clearCompleted() async {
    logDebug('Clearing completed downloads');
    await _downloadRepository.clearCompleted();
  }

  /// 开始下载任务
  Future<void> _startDownload(DownloadTask task) async {
    if (_activeCancelTokens.containsKey(task.id)) {
      logDebug('Task already downloading: ${task.id}');
      return;
    }
    
    logDebug('Starting download for track: ${task.trackId}');
    
    final cancelToken = CancelToken();
    _activeCancelTokens[task.id] = cancelToken;
    _activeDownloads++;
    
    try {
      // 更新状态为下载中
      await _downloadRepository.updateTaskStatus(task.id, DownloadStatus.downloading);
      
      // 获取歌曲信息
      final track = await _trackRepository.getById(task.trackId);
      if (track == null) {
        throw Exception('Track not found: ${task.trackId}');
      }
      
      // 获取音频 URL
      String audioUrl;
      if (!_sourceManager.needsRefresh(track) && track.audioUrl != null) {
        audioUrl = track.audioUrl!;
      } else {
        final refreshedTrack = await _sourceManager.refreshAudioUrl(track);
        audioUrl = refreshedTrack.audioUrl!;
        await _trackRepository.save(refreshedTrack);
      }
      
      // 确定保存路径
      final savePath = await _getDownloadPath(track, task);
      final tempPath = '$savePath.downloading';
      
      // 确保目录存在
      final dir = Directory(p.dirname(savePath));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      
      // 断点续传：检查是否有已下载的部分
      int resumePosition = 0;
      final tempFile = File(tempPath);
      if (task.canResume && task.tempFilePath == tempPath && await tempFile.exists()) {
        resumePosition = await tempFile.length();
        logDebug('Resuming download from position: $resumePosition');
      } else if (await tempFile.exists()) {
        // 临时文件存在但不匹配，删除重新下载
        await tempFile.delete();
      }
      
      // 保存临时文件路径到任务
      task.tempFilePath = tempPath;
      await _downloadRepository.saveTask(task);
      
      // 进度更新节流：避免过于频繁的 UI 更新导致 Windows 线程问题
      DateTime lastProgressUpdate = DateTime.now();
      double lastProgress = 0.0;
      const progressUpdateInterval = AppConstants.downloadProgressThrottleInterval;
      
      // 准备下载选项（支持断点续传）
      final options = Options(
        headers: resumePosition > 0 ? {'Range': 'bytes=$resumePosition-'} : null,
      );
      
      // 下载文件（使用临时路径）
      await _dio.download(
        audioUrl,
        tempPath,
        cancelToken: cancelToken,
        deleteOnError: false, // 保留部分下载的文件用于续传
        options: options,
        onReceiveProgress: (received, total) {
          // 断点续传时需要加上已下载部分
          final actualReceived = received + resumePosition;
          final actualTotal = total != -1 ? total + resumePosition : task.totalBytes ?? -1;
          
          if (actualTotal > 0) {
            final progress = actualReceived / actualTotal;
            final now = DateTime.now();
            
            // 只在以下情况更新进度：
            // 1. 距离上次更新超过 500ms
            // 2. 进度变化超过 5%
            // 3. 下载完成 (100%)
            final shouldUpdate = now.difference(lastProgressUpdate) >= progressUpdateInterval ||
                (progress - lastProgress) >= 0.05 ||
                progress >= 1.0;
            
            if (shouldUpdate) {
              lastProgressUpdate = now;
              lastProgress = progress;
              _downloadRepository.updateTaskProgress(task.id, progress, actualReceived, actualTotal);
              _progressController.add(DownloadProgressEvent(
                taskId: task.id,
                trackId: task.trackId,
                progress: progress,
                downloadedBytes: actualReceived,
                totalBytes: actualTotal,
              ));
            }
          }
        },
      );
      
      // 下载完成，将临时文件重命名为正式文件
      await tempFile.rename(savePath);

      // 获取 VideoDetail（用于保存完整元数据）
      VideoDetail? videoDetail;
      final videoDir = Directory(p.dirname(savePath));
      final metadataFile = File(p.join(videoDir.path, 'metadata.json'));

      // 检查是否已有完整的 metadata（多P视频只获取一次）
      bool hasFullMetadata = false;
      if (await metadataFile.exists()) {
        try {
          final existing = jsonDecode(await metadataFile.readAsString());
          hasFullMetadata = existing['viewCount'] != null;
        } catch (_) {}
      }

      // 如果没有完整 metadata，尝试获取 VideoDetail
      if (!hasFullMetadata && track.sourceType == SourceType.bilibili) {
        try {
          final source = _sourceManager.getSource(SourceType.bilibili);
          if (source is BilibiliSource) {
            videoDetail = await source.getVideoDetail(track.sourceId);
          }
        } catch (e) {
          logDebug('Failed to get video detail: $e');
        }
      }

      // 计算在歌单中的顺序
      int? trackOrder;
      if (task.playlistDownloadTaskId != null) {
        final playlistTask = await _downloadRepository.getPlaylistTaskById(task.playlistDownloadTaskId!);
        if (playlistTask != null) {
          trackOrder = playlistTask.trackIds.indexOf(track.id);
          if (trackOrder < 0) trackOrder = null;
        }
      }

      // 保存元数据
      await _saveMetadata(track, savePath, videoDetail: videoDetail, order: trackOrder);
      
      // 更新歌曲的下载路径
      track.downloadedPath = savePath;
      await _trackRepository.save(track);
      
      // 更新任务状态为已完成
      await _downloadRepository.updateTaskStatus(task.id, DownloadStatus.completed);
      
      logDebug('Download completed for track: ${track.title}');
      
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        logDebug('Download cancelled for task: ${task.id}');
        // 保存已下载的字节数用于续传
        await _saveResumeProgress(task);
      } else {
        logError('Download failed for task: ${task.id}: ${e.message}');
        // 保存已下载的字节数用于续传
        await _saveResumeProgress(task);
        await _downloadRepository.updateTaskStatus(
          task.id,
          DownloadStatus.failed,
          errorMessage: e.message ?? 'Network error',
        );
      }
    } catch (e, stack) {
      logError('Download failed for task: ${task.id}: $e', e, stack);
      // 保存已下载的字节数用于续传
      await _saveResumeProgress(task);
      await _downloadRepository.updateTaskStatus(
        task.id,
        DownloadStatus.failed,
        errorMessage: e.toString(),
      );
    } finally {
      _activeCancelTokens.remove(task.id);
      _activeDownloads--;
      // 下载完成后触发调度，继续下一个任务（事件驱动）
      _triggerSchedule();
    }
  }
  
  /// 保存断点续传进度
  Future<void> _saveResumeProgress(DownloadTask task) async {
    if (task.tempFilePath == null) return;
    
    try {
      final tempFile = File(task.tempFilePath!);
      if (await tempFile.exists()) {
        final downloadedBytes = await tempFile.length();
        task.downloadedBytes = downloadedBytes;
        await _downloadRepository.saveTask(task);
        logDebug('Saved resume progress: $downloadedBytes bytes for task ${task.id}');
      }
    } catch (e) {
      logDebug('Failed to save resume progress: $e');
    }
  }

  /// 获取下载保存路径
  Future<String> _getDownloadPath(Track track, DownloadTask task) async {
    final settings = await _settingsRepository.get();
    
    // 获取基础下载目录
    String baseDir;
    if (settings.customDownloadDir != null && settings.customDownloadDir!.isNotEmpty) {
      baseDir = settings.customDownloadDir!;
    } else {
      baseDir = await _getDefaultDownloadDir();
    }
    
    // 确定子目录
    String subDir;
    if (task.playlistDownloadTaskId != null) {
      // 从歌单下载任务获取歌单名
      final playlistTask = await _downloadRepository.getPlaylistTaskById(task.playlistDownloadTaskId!);
      if (playlistTask != null) {
        subDir = _sanitizeFileName(playlistTask.playlistName);
      } else {
        subDir = '未分类';
      }
    } else {
      subDir = '未分类';
    }
    
    // 视频文件夹名
    final videoFolder = _sanitizeFileName(track.parentTitle ?? track.title);
    
    // 音频文件名
    String fileName;
    if (track.isPartOfMultiPage && track.pageNum != null) {
      fileName = 'P${track.pageNum!.toString().padLeft(2, '0')} - ${_sanitizeFileName(track.title)}.m4a';
    } else {
      fileName = 'audio.m4a';
    }
    
    return p.join(baseDir, subDir, videoFolder, fileName);
  }

  /// 获取默认下载目录
  Future<String> _getDefaultDownloadDir() async {
    if (Platform.isAndroid) {
      // Android: 外部存储/Music/FMP/
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        // 尝试使用 Music 目录
        final musicDir = Directory(p.join(extDir.parent.parent.parent.parent.path, 'Music', 'FMP'));
        return musicDir.path;
      }
      // 回退到应用目录
      final appDir = await getApplicationDocumentsDirectory();
      return p.join(appDir.path, 'FMP');
    } else if (Platform.isWindows) {
      // Windows: 用户文档/FMP/
      final docsDir = await getApplicationDocumentsDirectory();
      return p.join(docsDir.path, 'FMP');
    } else {
      // 其他平台
      final appDir = await getApplicationDocumentsDirectory();
      return p.join(appDir.path, 'FMP');
    }
  }

  /// 清理文件名中的特殊字符
  String _sanitizeFileName(String name) {
    // 将特殊字符转换为全角字符
    const replacements = {
      '/': '／',  // U+FF0F
      '\\': '＼', // U+FF3C
      ':': '：',  // U+FF1A
      '*': '＊',  // U+FF0A
      '?': '？',  // U+FF1F
      '"': '＂',  // U+FF02
      '<': '＜',  // U+FF1C
      '>': '＞',  // U+FF1E
      '|': '｜',  // U+FF5C
    };
    
    String result = name;
    for (final entry in replacements.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    
    // 移除首尾空格和点
    result = result.trim();
    while (result.endsWith('.')) {
      result = result.substring(0, result.length - 1);
    }
    
    // 限制长度 (Windows 路径限制考虑)
    if (result.length > 200) {
      result = result.substring(0, 200);
    }
    
    return result.isEmpty ? 'untitled' : result;
  }

  /// 保存元数据
  /// [order] 在歌单中的顺序位置
  Future<void> _saveMetadata(Track track, String audioPath, {VideoDetail? videoDetail, int? order}) async {
    final settings = await _settingsRepository.get();
    final videoDir = Directory(p.dirname(audioPath));

    // 保存歌曲元数据
    final metadata = <String, dynamic>{
      // 基础信息
      'sourceId': track.sourceId,
      'sourceType': track.sourceType.name,
      'title': track.title,
      'artist': track.artist,
      'durationMs': track.durationMs,
      'cid': track.cid,
      'pageNum': track.pageNum,
      'parentTitle': track.parentTitle,
      'thumbnailUrl': track.thumbnailUrl,
      'downloadedAt': DateTime.now().toIso8601String(),
      // 歌单顺序
      'order': order,
    };

    // 添加 VideoDetail 扩展信息
    if (videoDetail != null) {
      metadata.addAll({
        'description': videoDetail.description,
        'viewCount': videoDetail.viewCount,
        'likeCount': videoDetail.likeCount,
        'coinCount': videoDetail.coinCount,
        'favoriteCount': videoDetail.favoriteCount,
        'shareCount': videoDetail.shareCount,
        'danmakuCount': videoDetail.danmakuCount,
        'commentCount': videoDetail.commentCount,
        'publishDate': videoDetail.publishDate.toIso8601String(),
        'ownerName': videoDetail.ownerName,
        'ownerFace': videoDetail.ownerFace,
        'ownerId': videoDetail.ownerId,
        'hotComments': videoDetail.hotComments.map((c) => {
          'content': c.content,
          'memberName': c.memberName,
          'memberAvatar': c.memberAvatar,
          'likeCount': c.likeCount,
        }).toList(),
      });
    }

    final metadataFile = File(p.join(videoDir.path, 'metadata.json'));
    await metadataFile.writeAsString(jsonEncode(metadata));

    // 下载封面（如果设置允许）
    if (settings.downloadImageOption != DownloadImageOption.none && track.thumbnailUrl != null) {
      try {
        final coverPath = p.join(videoDir.path, 'cover.jpg');
        await _dio.download(track.thumbnailUrl!, coverPath);
      } catch (e) {
        logDebug('Failed to download cover: $e');
      }
    }

    // 下载UP主头像（如果设置为"封面和头像"且有头像URL）
    if (settings.downloadImageOption == DownloadImageOption.coverAndAvatar &&
        videoDetail != null &&
        videoDetail.ownerFace.isNotEmpty) {
      try {
        final avatarPath = p.join(videoDir.path, 'avatar.jpg');
        await _dio.download(videoDetail.ownerFace, avatarPath);
      } catch (e) {
        logDebug('Failed to download avatar: $e');
      }
    }
  }

  /// 获取下载目录信息
  Future<DownloadDirInfo> getDownloadDirInfo() async {
    final settings = await _settingsRepository.get();
    final downloadDir = settings.customDownloadDir ?? await _getDefaultDownloadDir();
    
    final dir = Directory(downloadDir);
    int totalSize = 0;
    int fileCount = 0;
    
    if (await dir.exists()) {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          final stat = await entity.stat();
          totalSize += stat.size;
          fileCount++;
        }
      }
    }
    
    return DownloadDirInfo(
      path: downloadDir,
      totalSize: totalSize,
      fileCount: fileCount,
    );
  }

  /// 同步本地下载文件与数据库 Track 记录
  /// 
  /// 扫描下载目录中的所有 metadata.json 文件，
  /// 与数据库中的 Track 进行匹配，并更新 downloadedPath。
  /// 
  /// 返回：更新的 Track 数量
  Future<int> syncDownloadedFiles() async {
    logDebug('Starting download sync...');
    
    final settings = await _settingsRepository.get();
    final downloadDir = settings.customDownloadDir ?? await _getDefaultDownloadDir();
    
    final dir = Directory(downloadDir);
    if (!await dir.exists()) {
      logDebug('Download directory does not exist');
      return 0;
    }
    
    int updatedCount = 0;
    
    // 遍历所有子目录（歌单文件夹）
    await for (final playlistEntity in dir.list()) {
      if (playlistEntity is! Directory) continue;
      
      // 遍历视频文件夹
      await for (final videoEntity in playlistEntity.list()) {
        if (videoEntity is! Directory) continue;
        
        final metadataFile = File(p.join(videoEntity.path, 'metadata.json'));
        if (!await metadataFile.exists()) continue;
        
        try {
          final content = await metadataFile.readAsString();
          final metadata = jsonDecode(content) as Map<String, dynamic>;
          
          final sourceId = metadata['sourceId'] as String?;
          final sourceTypeStr = metadata['sourceType'] as String?;
          final cid = metadata['cid'] as int?;
          final pageNum = metadata['pageNum'] as int?;
          
          if (sourceId == null || sourceTypeStr == null) continue;
          
          final sourceType = SourceType.values.firstWhere(
            (e) => e.name == sourceTypeStr,
            orElse: () => SourceType.bilibili,
          );
          
          // 扫描该视频文件夹下的所有 .m4a 文件
          await for (final audioEntity in videoEntity.list()) {
            if (audioEntity is! File || !audioEntity.path.endsWith('.m4a')) continue;
            
            final audioPath = audioEntity.path;
            
            // 确定这个音频文件对应的 pageNum
            int? audioPageNum = pageNum;
            final fileName = p.basenameWithoutExtension(audioPath);
            final pageMatch = RegExp(r'^P(\d+)').firstMatch(fileName);
            if (pageMatch != null) {
              audioPageNum = int.tryParse(pageMatch.group(1)!);
            }
            
            // 查找匹配的 Track
            Track? track;
            if (cid != null || audioPageNum != null) {
              // 尝试精确匹配
              track = await _trackRepository.findBestMatchForRefresh(
                sourceId,
                sourceType,
                cid: cid,
                pageNum: audioPageNum,
              );
            } else {
              // 简单匹配
              track = await _trackRepository.getBySourceId(sourceId, sourceType);
            }
            
            if (track != null && track.downloadedPath != audioPath) {
              // 检查文件是否真实存在
              if (await File(audioPath).exists()) {
                track.downloadedPath = audioPath;
                await _trackRepository.save(track);
                updatedCount++;
                logDebug('Updated downloadedPath for track: ${track.title}');
              }
            }
          }
        } catch (e) {
          logDebug('Error processing metadata: ${metadataFile.path}, $e');
        }
      }
    }
    
    logDebug('Download sync completed. Updated $updatedCount tracks');
    return updatedCount;
  }
}

/// 下载进度事件
class DownloadProgressEvent {
  final int taskId;
  final int trackId;
  final double progress;
  final int downloadedBytes;
  final int? totalBytes;
  
  DownloadProgressEvent({
    required this.taskId,
    required this.trackId,
    required this.progress,
    required this.downloadedBytes,
    this.totalBytes,
  });
}

/// 下载目录信息
class DownloadDirInfo {
  final String path;
  final int totalSize;
  final int fileCount;
  
  DownloadDirInfo({
    required this.path,
    required this.totalSize,
    required this.fileCount,
  });
  
  /// 格式化大小显示
  String get formattedSize {
    if (totalSize < 1024) {
      return '$totalSize B';
    } else if (totalSize < 1024 * 1024) {
      return '${(totalSize / 1024).toStringAsFixed(1)} KB';
    } else if (totalSize < 1024 * 1024 * 1024) {
      return '${(totalSize / 1024 / 1024).toStringAsFixed(1)} MB';
    } else {
      return '${(totalSize / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
    }
  }
}
