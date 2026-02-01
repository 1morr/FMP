import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';
import '../../data/models/download_task.dart';
import '../../data/models/track.dart';
import '../../data/models/playlist.dart';
import '../../data/models/settings.dart';
import '../../data/models/video_detail.dart';
import '../../data/repositories/download_repository.dart';
import '../../data/repositories/track_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/sources/source_provider.dart';
import '../../data/sources/bilibili_source.dart';
import '../../data/sources/youtube_source.dart';
import 'download_path_utils.dart';

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
  
  /// 下载完成事件流控制器
  final _completionController = StreamController<DownloadCompletionEvent>.broadcast();
  
  /// 下载完成事件流（用于通知 UI 更新缓存）
  Stream<DownloadCompletionEvent> get completionStream => _completionController.stream;
  
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
  
  /// 全局进度更新节流（避免多个并发下载时淹没 Windows 消息队列）
  DateTime _lastGlobalProgressUpdate = DateTime.now();
  
  /// 待发送的进度更新（用于批量处理）
  final Map<int, DownloadProgressEvent> _pendingProgressUpdates = {};
  
  /// 进度更新定时器
  Timer? _progressUpdateTimer;

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
    
    // 清除已完成和失败的任务（A2: 启动时清理）
    final clearedCount = await _downloadRepository.clearCompletedAndErrorTasks();
    if (clearedCount > 0) {
      logDebug('Cleared $clearedCount completed/error tasks at startup');
    }
    
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
    _progressUpdateTimer?.cancel();
    _scheduleController.close();
    _progressController.close();
    _completionController.close();
    
    // 取消所有进行中的下载
    for (final cancelToken in _activeCancelTokens.values) {
      cancelToken.cancel('Service disposed');
    }
    _activeCancelTokens.clear();
    _pendingProgressUpdates.clear();
  }
  
  /// 刷新待发送的进度更新（在主线程调用）
  void _flushPendingProgressUpdates() {
    if (_pendingProgressUpdates.isEmpty) return;
    
    // 复制并清空待发送列表
    final updates = Map<int, DownloadProgressEvent>.from(_pendingProgressUpdates);
    _pendingProgressUpdates.clear();
    
    // 批量发送所有待处理的进度更新
    for (final event in updates.values) {
      _progressController.add(event);
    }
    
    _lastGlobalProgressUpdate = DateTime.now();
  }
  
  /// 添加进度更新（使用全局节流）
  void _addProgressUpdate(DownloadProgressEvent event) {
    // 将更新放入待发送队列（相同 taskId 会覆盖旧的更新）
    _pendingProgressUpdates[event.taskId] = event;
    
    final now = DateTime.now();
    final timeSinceLastUpdate = now.difference(_lastGlobalProgressUpdate);
    
    // 全局节流：最多每 300ms 发送一次所有待处理的更新
    // 这比每个下载 500ms 更激进，但因为是全局的所以总更新频率更低
    const globalThrottleInterval = Duration(milliseconds: 300);
    
    if (timeSinceLastUpdate >= globalThrottleInterval) {
      // 立即刷新
      _progressUpdateTimer?.cancel();
      _flushPendingProgressUpdates();
    } else {
      // 设置定时器在节流间隔后刷新
      _progressUpdateTimer?.cancel();
      _progressUpdateTimer = Timer(
        globalThrottleInterval - timeSinceLastUpdate,
        _flushPendingProgressUpdates,
      );
    }
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

  /// 手动触发下载调度（公开方法，用于批量添加后统一启动下载）
  void triggerSchedule() {
    _triggerSchedule();
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
  /// 
  /// [fromPlaylist] 必须提供，歌曲必须属于某个歌单才能下载
  /// [order] 在歌单中的顺序位置（从0开始）
  /// [skipSchedule] 为 true 时不触发下载调度（用于批量添加）
  Future<DownloadTask?> addTrackDownload(
    Track track, {
    required Playlist fromPlaylist,
    int? order,
    bool skipSchedule = false,
  }) async {
    logDebug('Adding download task for track: ${track.title}');

    final playlistId = fromPlaylist.id;

    // 计算下载路径（运行时计算，不再依赖预计算路径）
    final baseDir = await DownloadPathUtils.getDefaultBaseDir(_settingsRepository);
    final downloadPath = DownloadPathUtils.computeDownloadPath(
      baseDir: baseDir,
      playlistName: fromPlaylist.name,
      track: track,
    );

    // 检查文件是否已存在
    if (await File(downloadPath).exists()) {
      logDebug('File already exists at path: $downloadPath');
      return null; // 跳过下载
    }

    // A2: 按 savePath 去重（而非 trackId）
    // 这允许同一首歌下载到不同歌单（不同路径）
    final existingTask = await _downloadRepository.getTaskBySavePath(downloadPath);
    if (existingTask != null) {
      if (existingTask.isCompleted) {
        // 任务已完成但文件不存在，清理记录并重新下载
        logDebug('Downloaded file missing, re-queueing: ${track.title}');
        await _downloadRepository.deleteTask(existingTask.id);
      } else if (!existingTask.isFailed) {
        logDebug('Download task already exists for path: $downloadPath');
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
      ..playlistName = fromPlaylist.name
      ..playlistId = playlistId
      ..savePath = downloadPath  // 保存计划路径用于去重
      ..order = order
      ..status = DownloadStatus.pending
      ..priority = priority
      ..createdAt = DateTime.now();

    final savedTask = await _downloadRepository.saveTask(task);

    // 触发调度（事件驱动），批量添加时跳过
    if (!skipSchedule) {
      _triggerSchedule();
    }

    return savedTask;
  }

  /// 添加歌单下载任务（以单曲形式下载所有歌曲）
  /// 返回添加的下载任务数量
  Future<int> addPlaylistDownload(Playlist playlist) async {
    logDebug('Adding playlist download: ${playlist.name}');

    // 获取歌单中的所有歌曲
    final tracks = await _trackRepository.getByIds(playlist.trackIds);
    if (tracks.isEmpty) {
      logDebug('Playlist has no tracks: ${playlist.name}');
      return 0;
    }

    // 下载歌单封面
    await _downloadPlaylistCover(playlist);

    // 为每个歌曲创建下载任务（批量添加，不立即触发调度）
    int addedCount = 0;
    for (int i = 0; i < tracks.length; i++) {
      final task = await addTrackDownload(
        tracks[i],
        fromPlaylist: playlist,
        order: i,
        skipSchedule: true,  // 批量添加时跳过调度
      );
      if (task != null) {
        addedCount++;
      }
    }

    // 所有任务添加完成后，统一触发调度
    if (addedCount > 0) {
      _triggerSchedule();
    }

    logDebug('Added $addedCount download tasks for playlist: ${playlist.name}');
    return addedCount;
  }

  /// 下载歌单封面到分类文件夹
  ///
  /// 封面来源逻辑：
  /// - Bilibili 歌单：使用 playlist.coverUrl（API 返回的收藏夹封面）
  /// - YouTube/手动创建歌单：使用第一首歌曲的 thumbnailUrl
  /// 
  /// 总是覆盖已存在的 playlist_cover.jpg（获取最新封面）
  Future<void> _downloadPlaylistCover(Playlist playlist) async {
    String? coverUrl;

    // 根据歌单类型选择封面来源
    if (playlist.importSourceType == SourceType.bilibili) {
      // Bilibili 歌单：使用 API 返回的封面
      coverUrl = playlist.coverUrl;
    } else {
      // YouTube/手动创建歌单：使用第一首歌曲的封面
      if (playlist.trackIds.isNotEmpty) {
        final firstTrack = await _trackRepository.getById(playlist.trackIds.first);
        coverUrl = firstTrack?.thumbnailUrl;
      }
    }

    if (coverUrl == null || coverUrl.isEmpty) {
      logDebug('No cover URL available for playlist: ${playlist.name}');
      return;
    }

    try {
      // 获取基础下载目录
      final baseDir = await DownloadPathUtils.getDefaultBaseDir(_settingsRepository);

      // 歌单文件夹路径
      final subDir = _sanitizeFileName(playlist.name);
      final playlistFolder = Directory(p.join(baseDir, subDir));

      // 确保目录存在
      if (!await playlistFolder.exists()) {
        await playlistFolder.create(recursive: true);
      }

      // 下载封面到歌单文件夹（总是覆盖）
      final coverPath = p.join(playlistFolder.path, 'playlist_cover.jpg');
      await _dio.download(coverUrl, coverPath);
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

  /// 清除已完成和失败的任务（A1: 用于更改下载路径时）
  Future<int> clearCompletedAndErrorTasks() async {
    logDebug('Clearing completed and error tasks');
    return await _downloadRepository.clearCompletedAndErrorTasks();
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
      
      // 进度更新变量（用于检测显著变化）
      double lastProgress = 0.0;
      
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
            
            // 只在进度变化超过 2% 或下载完成时更新
            // 这是第一层过滤，减少需要处理的更新数量
            final shouldUpdate = (progress - lastProgress) >= 0.02 || progress >= 1.0;
            
            if (shouldUpdate) {
              lastProgress = progress;
              
              // 更新数据库（这是本地操作，不会导致线程问题）
              _downloadRepository.updateTaskProgress(task.id, progress, actualReceived, actualTotal);
              
              // 使用全局节流机制发送 UI 更新
              // 这会批量处理所有下载任务的进度，避免淹没 Windows 消息队列
              _addProgressUpdate(DownloadProgressEvent(
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
      if (!hasFullMetadata) {
        try {
          if (track.sourceType == SourceType.bilibili) {
            final source = _sourceManager.getSource(SourceType.bilibili);
            if (source is BilibiliSource) {
              videoDetail = await source.getVideoDetail(track.sourceId);
            }
          } else if (track.sourceType == SourceType.youtube) {
            final source = _sourceManager.getSource(SourceType.youtube);
            if (source is YouTubeSource) {
              videoDetail = await source.getVideoDetail(track.sourceId);
            }
          }
        } catch (e) {
          logDebug('Failed to get video detail: $e');
        }
      }

      // 保存元数据（使用 task 中保存的 order）
      await _saveMetadata(track, savePath, videoDetail: videoDetail, order: task.order);

      // A3: 验证文件存在后才保存下载路径到 Track
      if (await File(savePath).exists()) {
        await _trackRepository.addDownloadPath(track.id, task.playlistId, savePath);
      } else {
        logError('Download completed but file not found at: $savePath');
        throw Exception('Downloaded file not found at expected path');
      }
      
      // 更新任务状态为已完成
      await _downloadRepository.updateTaskStatus(task.id, DownloadStatus.completed);
      
      logDebug('Download completed for track: ${track.title}');
      
      // 发送下载完成事件，通知 UI 更新缓存
      _completionController.add(DownloadCompletionEvent(
        taskId: task.id,
        trackId: task.trackId,
        playlistId: task.playlistId,
        savePath: savePath,
      ));
      
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
  /// 
  /// 运行时计算路径（不再依赖预计算路径）
  Future<String> _getDownloadPath(Track track, DownloadTask task) async {
    final baseDir = await DownloadPathUtils.getDefaultBaseDir(_settingsRepository);
    return DownloadPathUtils.computeDownloadPath(
      baseDir: baseDir,
      playlistName: task.playlistName,
      track: track,
    );
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
        'channelId': videoDetail.channelId,
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

    // 下載創作者頭像到集中式文件夾（如果設置為"封面和頭像"且有頭像URL）
    if (settings.downloadImageOption == DownloadImageOption.coverAndAvatar &&
        videoDetail != null &&
        videoDetail.ownerFace.isNotEmpty) {
      try {
        // 獲取創作者 ID
        final creatorId = track.sourceType == SourceType.bilibili
            ? videoDetail.ownerId.toString()
            : videoDetail.channelId;

        // 只有當有有效的創作者 ID 時才下載頭像
        if (creatorId.isNotEmpty && creatorId != '0') {
          final baseDir = await DownloadPathUtils.getDefaultBaseDir(_settingsRepository);

          // 確保頭像目錄存在
          await DownloadPathUtils.ensureAvatarDirExists(baseDir, track.sourceType);

          // 計算頭像路徑並下載（總是覆蓋以獲取最新頭像）
          final avatarPath = DownloadPathUtils.getAvatarPath(
            baseDir: baseDir,
            sourceType: track.sourceType,
            creatorId: creatorId,
          );
          await _dio.download(videoDetail.ownerFace, avatarPath);
        }
      } catch (e) {
        logDebug('Failed to download avatar: $e');
      }
    }
  }

  /// 获取下载目录信息
  Future<DownloadDirInfo> getDownloadDirInfo() async {
    final downloadDir = await DownloadPathUtils.getDefaultBaseDir(_settingsRepository);
    
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

/// 下载完成事件
class DownloadCompletionEvent {
  final int taskId;
  final int trackId;
  final int? playlistId;
  final String savePath;

  DownloadCompletionEvent({
    required this.taskId,
    required this.trackId,
    this.playlistId,
    required this.savePath,
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
