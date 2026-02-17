import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

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
import '../../data/sources/base_source.dart';
import '../../data/sources/bilibili_source.dart';
import '../../data/sources/youtube_source.dart';
import 'download_path_utils.dart';

/// 下载任务添加结果
enum DownloadResult {
  /// 新建任务成功
  created,
  /// 已有下载路径（已下载）
  alreadyDownloaded,
  /// 已有下载任务（下载中/暂停/待下载）
  taskExists,
}

/// 下载服务
class DownloadService with Logging {
  final DownloadRepository _downloadRepository;
  final TrackRepository _trackRepository;
  final SettingsRepository _settingsRepository;
  final SourceManager _sourceManager;

  
  final Dio _dio;
  
  /// 正在进行的下载任务（保存 Isolate 和 ReceivePort 以支持取消）
  final Map<int, ({Isolate isolate, ReceivePort receivePort})> _activeDownloadIsolates = {};
  
  /// 旧的取消令牌（保留用于非 Isolate 下载，如果需要回退）
  final Map<int, CancelToken> _activeCancelTokens = {};
  
  /// 下载进度流控制器
  final _progressController = StreamController<DownloadProgressEvent>.broadcast();
  
  /// 下载进度流
  Stream<DownloadProgressEvent> get progressStream => _progressController.stream;
  
  /// 下载完成事件流控制器
  final _completionController = StreamController<DownloadCompletionEvent>.broadcast();
  
  /// 下载完成事件流（用于通知 UI 更新缓存）
  Stream<DownloadCompletionEvent> get completionStream => _completionController.stream;

  /// 下载失败事件流控制器
  final _failureController = StreamController<DownloadFailureEvent>.broadcast();

  /// 下载失败事件流（用于通知 UI 显示错误提示）
  Stream<DownloadFailureEvent> get failureStream => _failureController.stream;
  
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
  
  /// 待发送的进度更新（仅在内存中累积，由定时器统一处理）
  /// Key: taskId, Value: (trackId, progress, downloadedBytes, totalBytes)
  final Map<int, (int, double, int, int)> _pendingProgressUpdates = {};
  
  /// 进度更新定时器（主线程定时器，统一处理所有进度更新）
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
    
    // 启动进度更新定时器（在主线程中统一处理进度更新）
    _startProgressUpdateTimer();
    
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
    _failureController.close();
    
    // 取消所有进行中的 Isolate 下载
    for (final entry in _activeDownloadIsolates.values) {
      entry.receivePort.close();
      entry.isolate.kill();
    }
    _activeDownloadIsolates.clear();
    
    // 兼容旧的 CancelToken
    for (final cancelToken in _activeCancelTokens.values) {
      cancelToken.cancel('Service disposed');
    }
    _activeCancelTokens.clear();
    _pendingProgressUpdates.clear();
  }
  
  /// 刷新待发送的进度更新（在主线程定时器中调用）
  /// 注意：进度更新只发送到 stream，不写入数据库
  /// 这样可以避免 Isar watch 频繁触发 UI 重建
  void _flushPendingProgressUpdates() {
    if (_pendingProgressUpdates.isEmpty) return;
    
    // 复制并清空待发送列表
    final updates = Map<int, (int, double, int, int)>.from(_pendingProgressUpdates);
    _pendingProgressUpdates.clear();
    
    // 批量发送 UI 通知（进度只保存在内存中，不写数据库）
    for (final entry in updates.entries) {
      final taskId = entry.key;
      final (trackId, progress, downloadedBytes, totalBytes) = entry.value;
      
      // 只发送 UI 通知，不写数据库
      // 数据库只在下载完成/暂停/失败时更新
      _progressController.add(DownloadProgressEvent(
        taskId: taskId,
        trackId: trackId,
        progress: progress,
        downloadedBytes: downloadedBytes,
        totalBytes: totalBytes,
      ));
    }
  }
  
  /// 启动进度更新定时器（主线程定时器）
  void _startProgressUpdateTimer() {
    _progressUpdateTimer?.cancel();
    // 每 1000ms 在主线程中统一处理所有进度更新
    // 这样可以避免：
    // 1. 在 IO 线程中直接跨线程通信
    // 2. 过多消息导致 Windows PostMessage 队列溢出
    _progressUpdateTimer = Timer.periodic(
      const Duration(milliseconds: 1000),
      (_) => _flushPendingProgressUpdates(),
    );
  }
  
  /// 记录进度更新（仅更新内存，不触发任何 IO 或跨线程通信）
  /// 由 Dio 的 onReceiveProgress 回调调用（在 IO 线程中）
  void _recordProgressUpdate(int taskId, int trackId, double progress, int downloadedBytes, int totalBytes) {
    // 只更新内存中的 Map，完全线程安全（Dart 的 Map 操作是原子的）
    _pendingProgressUpdates[taskId] = (trackId, progress, downloadedBytes, totalBytes);
  }

  /// 启动调度器（事件驱动 + 周期检查）
  void _startScheduler() {
    // 事件驱动：监听调度请求
    _scheduleSubscription?.cancel();
    _scheduleSubscription = _scheduleController.stream.listen((_) {
      _scheduleDownloads();
    });
    
    // 周期检查：作为备份机制
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
        // 先更新状态为下载中（await 确保 DB 写入完成，UI 能立即看到变化）
        await _downloadRepository.updateTaskStatus(task.id, DownloadStatus.downloading);
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
  /// [skipSchedule] 为 true 时不触发下载调度（用于批量添加）
  ///
  /// 简化逻辑：
  /// 1. 有下载路径 → 返回 alreadyDownloaded
  /// 2. 有下载任务 → 返回 taskExists（不自动 resume）
  /// 3. 创建新任务 → 返回 created
  Future<DownloadResult> addTrackDownload(
    Track track, {
    required Playlist fromPlaylist,
    bool skipSchedule = false,
  }) async {
    logDebug('Adding download task for track: ${track.title}');

    final playlistId = fromPlaylist.id;
    final playlistName = fromPlaylist.name;

    // 1. 有下载路径 → 已下载
    if (track.isDownloadedForPlaylist(playlistId, playlistName: playlistName)) {
      logDebug('Track already downloaded for playlist: ${track.title}');
      return DownloadResult.alreadyDownloaded;
    }

    // 计算下载路径（运行时计算）
    final baseDir = await DownloadPathUtils.getDefaultBaseDir(_settingsRepository);
    final downloadPath = DownloadPathUtils.computeDownloadPath(
      baseDir: baseDir,
      playlistName: playlistName,
      track: track,
    );

    // 2. 有下载任务 → 返回 taskExists（不管状态，不自动 resume）
    final existingTask = await _downloadRepository.getTaskBySavePath(downloadPath);
    if (existingTask != null) {
      logDebug('Download task already exists for path: $downloadPath (status: ${existingTask.status})');
      return DownloadResult.taskExists;
    }

    // 3. 创建新任务
    final priority = await _downloadRepository.getNextPriority();
    final task = DownloadTask()
      ..trackId = track.id
      ..playlistName = playlistName
      ..playlistId = playlistId
      ..savePath = downloadPath
      ..status = DownloadStatus.pending
      ..priority = priority
      ..createdAt = DateTime.now();

    await _downloadRepository.saveTask(task);

    // 触发调度（事件驱动），批量添加时跳过
    if (!skipSchedule) {
      _triggerSchedule();
    }

    return DownloadResult.created;
  }

  /// 添加歌单下载任务（批量一次性添加所有歌曲）
  ///
  /// 简化逻辑：
  /// 1. 有下载路径的 track → 跳过
  /// 2. 有下载任务的 track → 跳过（不自动 resume）
  /// 3. 其他 → 创建新任务
  ///
  /// 返回新创建的下载任务数量
  Future<int> addPlaylistDownload(Playlist playlist) async {
    logDebug('Adding playlist download: ${playlist.name}');

    // 获取歌单中的所有歌曲
    final tracks = await _trackRepository.getByIds(playlist.trackIds);
    if (tracks.isEmpty) {
      logDebug('Playlist has no tracks: ${playlist.name}');
      return 0;
    }

    try {
      final playlistId = playlist.id;
      final playlistName = playlist.name;

      // 1. 过滤掉已有下载路径的 track
      final tracksNeedDownload = <Track>[];
      for (final track in tracks) {
        if (!track.isDownloadedForPlaylist(playlistId, playlistName: playlistName)) {
          tracksNeedDownload.add(track);
        }
      }

      if (tracksNeedDownload.isEmpty) {
        logDebug('All tracks already downloaded: ${playlist.name}');
        return 0;
      }

      // 2. 批量计算下载路径
      final baseDir = await DownloadPathUtils.getDefaultBaseDir(_settingsRepository);
      final trackPaths = <Track, String>{};
      for (final track in tracksNeedDownload) {
        trackPaths[track] = DownloadPathUtils.computeDownloadPath(
          baseDir: baseDir,
          playlistName: playlistName,
          track: track,
        );
      }

      // 3. 批量查询已有任务（按 savePath 去重）
      final pathsToCheck = trackPaths.values.toList();
      final existingTasks = await _downloadRepository.getTasksBySavePaths(pathsToCheck);

      // 4. 过滤掉已有任务的 track，创建新任务
      final newTasks = <DownloadTask>[];
      final basePriority = await _downloadRepository.getNextPriority();
      int skippedCount = 0;

      for (final entry in trackPaths.entries) {
        final track = entry.key;
        final downloadPath = entry.value;
        final existingTask = existingTasks[downloadPath];

        // 有下载任务 → 跳过（不管状态，不自动 resume）
        if (existingTask != null) {
          skippedCount++;
          continue;
        }

        // 创建新任务
        newTasks.add(DownloadTask()
          ..trackId = track.id
          ..playlistName = playlistName
          ..playlistId = playlistId
          ..savePath = downloadPath
          ..status = DownloadStatus.pending
          ..priority = basePriority + newTasks.length
          ..createdAt = DateTime.now());
      }

      // 5. 批量保存新任务
      if (newTasks.isNotEmpty) {
        await _downloadRepository.saveTasks(newTasks);
      }

      logDebug('Added ${newTasks.length} new tasks, skipped $skippedCount existing tasks for playlist: ${playlist.name}');
      return newTasks.length;
    } finally {
      // 批量添加完成，触发调度
      _triggerSchedule();
    }
  }

  /// 暂停下载任务
  Future<void> pauseTask(int taskId) async {
    logDebug('Pausing download task: $taskId');
    
    // 取消正在进行的 Isolate 下载
    final isolateInfo = _activeDownloadIsolates.remove(taskId);
    if (isolateInfo != null) {
      isolateInfo.receivePort.close();
      isolateInfo.isolate.kill();
      _activeDownloads--;
    }
    
    // 兼容旧的 CancelToken（如果有的话）
    final cancelToken = _activeCancelTokens.remove(taskId);
    if (cancelToken != null) {
      cancelToken.cancel('User paused');
      if (isolateInfo == null) _activeDownloads--;
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
    
    // 取消正在进行的 Isolate 下载
    final isolateInfo = _activeDownloadIsolates.remove(taskId);
    if (isolateInfo != null) {
      isolateInfo.receivePort.close();
      isolateInfo.isolate.kill();
      _activeDownloads--;
    }
    
    // 兼容旧的 CancelToken
    final cancelToken = _activeCancelTokens.remove(taskId);
    if (cancelToken != null) {
      cancelToken.cancel('User cancelled');
      if (isolateInfo == null) _activeDownloads--;
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
    
    // 取消所有进行中的 Isolate 下载
    for (final entry in _activeDownloadIsolates.entries) {
      entry.value.receivePort.close();
      entry.value.isolate.kill();
    }
    _activeDownloadIsolates.clear();
    
    // 兼容旧的 CancelToken
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

    // 取消所有进行中的 Isolate 下载
    for (final entry in _activeDownloadIsolates.entries) {
      entry.value.receivePort.close();
      entry.value.isolate.kill();
    }
    _activeDownloadIsolates.clear();
    
    // 兼容旧的 CancelToken
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
    logDebug('Clearing completed and error tasks - calling repository');
    try {
      final result = await _downloadRepository.clearCompletedAndErrorTasks();
      logDebug('Clearing completed and error tasks - done, cleared $result tasks');
      return result;
    } catch (e, stackTrace) {
      logDebug('Clearing completed and error tasks - ERROR: $e');
      logDebug('StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// 根据用户设置构建音频流配置（与播放时使用相同逻辑）
  Future<AudioStreamConfig> _buildAudioStreamConfig(SourceType sourceType) async {
    final settings = await _settingsRepository.get();
    
    // 根据源类型选择流优先级
    final streamPriority = sourceType == SourceType.youtube
        ? settings.youtubeStreamPriorityList
        : settings.bilibiliStreamPriorityList;

    return AudioStreamConfig(
      qualityLevel: settings.audioQualityLevel,
      formatPriority: settings.audioFormatPriorityList,
      streamPriority: streamPriority,
    );
  }

  /// 开始下载任务
  Future<void> _startDownload(DownloadTask task) async {
    // 检查是否已经在下载（Isolate 或旧的 CancelToken）
    if (_activeDownloadIsolates.containsKey(task.id) || _activeCancelTokens.containsKey(task.id)) {
      logDebug('Task already downloading: ${task.id}');
      return;
    }
    
    logDebug('Starting download for track: ${task.trackId}');
    _activeDownloads++;
    String trackTitle = 'Track ${task.trackId}';

    try {
      // 状态已在 _scheduleDownloads 中更新为 downloading
      
      // 获取歌曲信息
      final track = await _trackRepository.getById(task.trackId);
      if (track == null) {
        throw Exception('Track not found: ${task.trackId}');
      }
      trackTitle = track.title;
      
      // 获取音频 URL（使用用户设置的音频配置，与播放时逻辑一致）
      final source = _sourceManager.getSource(track.sourceType);
      if (source == null) {
        throw Exception('No source available for ${track.sourceType}');
      }
      
      final config = await _buildAudioStreamConfig(track.sourceType);
      final streamResult = await source.getAudioStream(track.sourceId, config: config);
      final audioUrl = streamResult.url;
      
      // 更新 track 的 URL 信息
      track.audioUrl = audioUrl;
      track.audioUrlExpiry = DateTime.now().add(const Duration(hours: 1));
      track.updatedAt = DateTime.now();
      await _trackRepository.save(track);
      
      logDebug('Got audio stream for download: ${track.title}, '
          'quality=${config.qualityLevel}, bitrate=${streamResult.bitrate}');
      
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
      
      // 保存临时文件路径到任务（确保状态正确，因为传入的 task 对象可能是旧状态）
      task.tempFilePath = tempPath;
      task.status = DownloadStatus.downloading;
      await _downloadRepository.saveTask(task);
      
      // 使用 Isolate 进行下载，避免在主线程中进行网络 I/O
      // 这可以解决 Windows 上的 "Failed to post message to main thread" 错误
      final receivePort = ReceivePort();
      final headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': 'https://www.bilibili.com',
      };
      
      final isolate = await Isolate.spawn(
        _isolateDownload,
        _IsolateDownloadParams(
          url: audioUrl,
          savePath: tempPath,
          headers: headers,
          resumePosition: resumePosition,
          sendPort: receivePort.sendPort,
        ),
      );
      
      // 保存 Isolate 引用以支持取消
      _activeDownloadIsolates[task.id] = (isolate: isolate, receivePort: receivePort);
      
      // 监听来自 Isolate 的消息
      String? downloadError;
      bool wasCancelled = false;
      await for (final message in receivePort) {
        if (message is _IsolateMessage) {
          switch (message.type) {
            case _IsolateMessageType.progress:
              final data = message.data as Map<String, dynamic>;
              final progress = data['progress'] as double;
              final received = data['received'] as int;
              final total = data['total'] as int;
              _recordProgressUpdate(task.id, task.trackId, progress, received, total);
              break;
            case _IsolateMessageType.completed:
              receivePort.close();
              break;
            case _IsolateMessageType.error:
              downloadError = message.data as String;
              receivePort.close();
              break;
          }
        } else if (message == 'cancelled') {
          wasCancelled = true;
          receivePort.close();
          break;
        }
      }

      // 清理 Isolate 引用（不从 map 移除，由 finally 统一处理）
      isolate.kill();
      
      // 如果被取消，不抛异常，让 finally 处理
      if (wasCancelled) {
        logDebug('Download cancelled for task: ${task.id}');
        await _saveResumeProgress(task);
        return;
      }
      
      if (downloadError != null) {
        throw Exception('Download failed: $downloadError');
      }
      
      // 下载完成，将临时文件重命名为正式文件
      await tempFile.rename(savePath);

      // 获取 VideoDetail（用于保存完整元数据）
      VideoDetail? videoDetail;
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

      // 保存元数据（总是用最新数据覆盖）
      await _saveMetadata(track, savePath, videoDetail: videoDetail);

      // A3: 验证文件存在后才保存下载路径到 Track
      if (await File(savePath).exists()) {
        await _trackRepository.addDownloadPath(track.id, task.playlistId, task.playlistName, savePath);
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
      
    } catch (e, stack) {
      logError('Download failed for task: ${task.id}: $e', e, stack);
      await _handleDownloadFailure(task, trackTitle, e.toString());
    } finally {
      // 只在未被外部取消（pauseTask/cancelTask）时清理和递减
      // pauseTask/cancelTask 已经移除了 isolate 并递减了 _activeDownloads
      final wasStillActive = _activeDownloadIsolates.remove(task.id) != null;
      _activeCancelTokens.remove(task.id);
      if (wasStillActive) {
        _activeDownloads--;
      }
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

  /// 处理下载失败：保存续传进度、更新状态、发送失败事件
  Future<void> _handleDownloadFailure(DownloadTask task, String trackTitle, String errorMessage) async {
    await _saveResumeProgress(task);
    await _downloadRepository.updateTaskStatus(
      task.id,
      DownloadStatus.failed,
      errorMessage: errorMessage,
    );
    _failureController.add(DownloadFailureEvent(
      taskId: task.id,
      trackId: task.trackId,
      trackTitle: trackTitle,
      errorMessage: errorMessage,
    ));
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


  /// 保存元数据
  Future<void> _saveMetadata(Track track, String audioPath, {VideoDetail? videoDetail}) async {
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
      'pageCount': track.pageCount,
      'parentTitle': track.parentTitle,
      'thumbnailUrl': track.thumbnailUrl,
      'downloadedAt': DateTime.now().toIso8601String(),
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

    // 多P视频使用分P专属的 metadata 文件名，避免覆盖
    final metadataFileName = track.isPartOfMultiPage && track.pageNum != null
        ? 'metadata_P${track.pageNum!.toString().padLeft(2, '0')}.json'
        : 'metadata.json';
    final metadataFile = File(p.join(videoDir.path, metadataFileName));
    try {
      await metadataFile.writeAsString(jsonEncode(metadata));
    } on FileSystemException catch (e) {
      logWarning('Failed to save metadata for ${track.title}: $e');
      // 元数据保存失败不应阻止下载完成
    }

    // 下载封面（如果设置允许）
    if (settings.downloadImageOption != DownloadImageOption.none && track.thumbnailUrl != null) {
      try {
        final coverPath = p.join(videoDir.path, 'cover.jpg');
        await _dio.download(track.thumbnailUrl!, coverPath);
      } catch (e) {
        logDebug('Failed to download cover: $e');
      }
    }

    // 下載創作者頭像到視頻文件夾內（如果設置為\"封面和頭像\"且有頭像URL）
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

/// 下载失败事件
class DownloadFailureEvent {
  final int taskId;
  final int trackId;
  final String trackTitle;
  final String errorMessage;

  DownloadFailureEvent({
    required this.taskId,
    required this.trackId,
    required this.trackTitle,
    required this.errorMessage,
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

// ==================== Isolate 下载相关 ====================

/// Isolate 下载参数
class _IsolateDownloadParams {
  final String url;
  final String savePath;
  final Map<String, String> headers;
  final int resumePosition;
  final SendPort sendPort;

  _IsolateDownloadParams({
    required this.url,
    required this.savePath,
    required this.headers,
    required this.resumePosition,
    required this.sendPort,
  });
}

/// Isolate 下载消息类型
enum _IsolateMessageType {
  progress,
  completed,
  error,
}

/// Isolate 下载消息
class _IsolateMessage {
  final _IsolateMessageType type;
  final dynamic data;

  _IsolateMessage(this.type, this.data);
}

/// 在 Isolate 中执行下载（顶层函数）
Future<void> _isolateDownload(_IsolateDownloadParams params) async {
  final sendPort = params.sendPort;
  
  try {
    final client = HttpClient();
    client.connectionTimeout = AppConstants.downloadConnectTimeout;
    
    final request = await client.getUrl(Uri.parse(params.url));
    
    // 添加 headers
    params.headers.forEach((key, value) {
      request.headers.set(key, value);
    });
    
    // 断点续传
    if (params.resumePosition > 0) {
      request.headers.set('Range', 'bytes=${params.resumePosition}-');
    }
    
    final response = await request.close();
    
    if (response.statusCode >= 400) {
      sendPort.send(_IsolateMessage(_IsolateMessageType.error, 'HTTP ${response.statusCode}'));
      return;
    }
    
    final file = File(params.savePath);
    final sink = file.openWrite(mode: params.resumePosition > 0 ? FileMode.append : FileMode.write);
    
    final contentLength = response.contentLength;
    final totalBytes = contentLength > 0 ? contentLength + params.resumePosition : -1;
    int receivedBytes = params.resumePosition;
    double lastProgress = 0;
    
    await for (final chunk in response) {
      sink.add(chunk);
      receivedBytes += chunk.length;
      
      if (totalBytes > 0) {
        final progress = receivedBytes / totalBytes;
        // 每 5% 发送一次进度更新
        if ((progress - lastProgress) >= 0.05 || progress >= 1.0) {
          lastProgress = progress;
          sendPort.send(_IsolateMessage(_IsolateMessageType.progress, {
            'progress': progress,
            'received': receivedBytes,
            'total': totalBytes,
          }));
        }
      }
    }
    
    await sink.close();
    client.close();
    
    sendPort.send(_IsolateMessage(_IsolateMessageType.completed, null));
  } on SocketException catch (e) {
    sendPort.send(_IsolateMessage(
      _IsolateMessageType.error,
      '{"type":"network","message":"${e.message.replaceAll('"', r'\"')}"}',
    ));
  } on HttpException catch (e) {
    sendPort.send(_IsolateMessage(
      _IsolateMessageType.error,
      '{"type":"http","message":"${e.message.replaceAll('"', r'\"')}"}',
    ));
  } on FileSystemException catch (e) {
    sendPort.send(_IsolateMessage(
      _IsolateMessageType.error,
      '{"type":"filesystem","message":"${e.message.replaceAll('"', r'\"')}"}',
    ));
  } catch (e) {
    sendPort.send(_IsolateMessage(
      _IsolateMessageType.error,
      '{"type":"unknown","message":"$e"}',
    ));
  }
}
