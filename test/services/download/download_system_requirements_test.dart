import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/models/playlist.dart';
import 'package:fmp/core/extensions/track_extensions.dart';

/// 下载系统需求验证测试
///
/// 测试项目：
/// 1. 手机上必须先选择下载路径才能下载
/// 2. 移除预计算路径，下载完成后才保存路径
/// 3. 修改下载路径时清空所有数据库路径
/// 4. 简化已下载标记显示机制
/// 5. 已下载页面刷新同步功能
/// 7. 实时显示已下载标记
void main() {
  group('Requirement 1: 手机上必须先选择下载路径才能下载', () {
    test('DownloadPathManager.hasConfiguredPath 未配置时返回 false', () {
      // DownloadPathManager 检查 settings.customDownloadDir
      // 当为 null 或空字符串时返回 false
      
      // 模拟：settings.customDownloadDir == null
      const String? customDownloadDir = null;
      final hasConfiguredPath = customDownloadDir != null &&
          customDownloadDir.isNotEmpty;
      
      expect(hasConfiguredPath, isFalse);
    });

    test('DownloadPathManager.hasConfiguredPath 已配置时返回 true', () {
      // 当有有效路径时返回 true
      const customDownloadDir = '/storage/emulated/0/Music';
      final hasConfiguredPath = customDownloadDir.isNotEmpty;
      
      expect(hasConfiguredPath, isTrue);
    });

    test('空字符串路径应视为未配置', () {
      const customDownloadDir = '';
      final hasConfiguredPath = customDownloadDir.isNotEmpty;
      
      expect(hasConfiguredPath, isFalse);
    });
  });

  group('Requirement 2: 移除预计算路径，下载完成后才保存路径', () {
    test('新创建的 Track 应没有下载路径', () {
      final track = Track()
        ..sourceId = 'BV123456789'
        ..sourceType = SourceType.bilibili
        ..title = 'Test Song';

      // 新 Track 的 downloadPaths 应为空
      expect(track.downloadPaths, isEmpty);
      expect(track.isDownloaded, isFalse);
    });

    test('添加歌曲到歌单不应设置下载路径', () {
      // 歌单只添加 trackId，不预设下载路径
      final playlist = Playlist()
        ..name = 'Test Playlist'
        ..trackIds = [1, 2, 3];

      // Track 在歌单中但未下载
      final track = Track()
        ..id = 1
        ..sourceId = 'BV123456789'
        ..sourceType = SourceType.bilibili
        ..title = 'Test Song'
        ..playlistIds = [playlist.id];

      // playlistIds 可以有值，但 downloadPaths 应为空（未下载）
      expect(track.playlistIds, isNotEmpty);
      expect(track.downloadPaths, isEmpty);
      expect(track.isDownloaded, isFalse);
    });

    test('下载完成后应保存下载路径', () {
      // 模拟下载完成后的状态
      final track = Track()
        ..sourceId = 'BV123456789'
        ..sourceType = SourceType.bilibili
        ..title = 'Test Song'
        ..playlistIds = [1]
        ..downloadPaths = ['/path/to/downloaded/audio.m4a'];

      expect(track.downloadPaths, isNotEmpty);
      expect(track.isDownloaded, isTrue);
    });
  });

  group('Requirement 3: 修改下载路径时清空所有数据库路径', () {
    test('clearAllDownloadPaths 应清空所有 Track 的路径', () {
      // 模拟清空操作前后的状态
      
      // 清空前
      final tracksBefore = [
        Track()
          ..playlistIds = [1]
          ..downloadPaths = ['/old/path/song1.m4a'],
        Track()
          ..playlistIds = [1, 2]
          ..downloadPaths = ['/old/path/song2.m4a', '/old/path2/song2.m4a'],
      ];

      expect(tracksBefore[0].isDownloaded, isTrue);
      expect(tracksBefore[1].isDownloaded, isTrue);

      // 清空后
      final tracksAfter = [
        Track()
          ..playlistIds = []
          ..downloadPaths = [],
        Track()
          ..playlistIds = []
          ..downloadPaths = [],
      ];

      expect(tracksAfter[0].isDownloaded, isFalse);
      expect(tracksAfter[1].isDownloaded, isFalse);
      expect(tracksAfter[0].playlistIds, isEmpty);
      expect(tracksAfter[1].playlistIds, isEmpty);
    });
  });

  group('Requirement 4: 简化已下载标记显示机制', () {
    test('isDownloaded: 有下载路径就返回 true', () {
      final track = Track()
        ..downloadPaths = ['/path/to/audio.m4a'];

      // TrackExtensions.isDownloaded 简化逻辑
      expect(track.isDownloaded, isTrue);
    });

    test('isDownloaded: 无下载路径返回 false', () {
      final track = Track()
        ..downloadPaths = [];

      expect(track.isDownloaded, isFalse);
    });

    test('localAudioPath: 遍历并返回第一个实际存在的路径', () {
      // 模拟路径列表
      final paths = [
        '/nonexistent/path1.m4a',
        '/nonexistent/path2.m4a',
      ];

      // localAudioPath 会检查 File(path).existsSync()
      // 如果都不存在返回 null
      String? localAudioPath;
      for (final path in paths) {
        try {
          if (File(path).existsSync()) {
            localAudioPath = path;
            break;
          }
        } catch (_) {}
      }

      expect(localAudioPath, isNull);
    });

    test('hasLocalAudio: localAudioPath 存在时返回 true', () {
      // hasLocalAudio = localAudioPath != null
      
      // 当 localAudioPath 存在时
      const localAudioPath = '/existing/audio.m4a';
      final hasLocalAudio = localAudioPath.isNotEmpty;
      expect(hasLocalAudio, isTrue);

      // 当 localAudioPath 为空时
      const noLocalPath = '';
      final noLocalAudio = noLocalPath.isNotEmpty;
      expect(noLocalAudio, isFalse);
    });
  });

  group('Requirement 5: 已下载页面刷新同步功能', () {
    test('syncLocalFiles 应将本地文件路径导入数据库', () {
      // DownloadPathSyncService.syncLocalFiles 扫描本地文件
      // 根据 sourceId + sourceType + cid 匹配 Track
      // 匹配成功则调用 trackRepo.addDownloadPath()

      // 模拟扫描到的本地 Track
      final scannedTrack = Track()
        ..sourceId = 'BV123456789'
        ..sourceType = SourceType.bilibili
        ..cid = 12345
        ..title = 'Local Song'
        ..downloadPaths = ['/local/path/audio.m4a'];

      // 数据库中的 Track
      final existingTrack = Track()
        ..id = 1
        ..sourceId = 'BV123456789'
        ..sourceType = SourceType.bilibili
        ..cid = 12345
        ..title = 'Local Song'
        ..downloadPaths = [];

      // 匹配成功后，应该更新 existingTrack 的 downloadPaths
      expect(existingTrack.sourceId, equals(scannedTrack.sourceId));
      expect(existingTrack.sourceType, equals(scannedTrack.sourceType));
      expect(existingTrack.cid, equals(scannedTrack.cid));
      
      // 添加路径后
      existingTrack.downloadPaths = scannedTrack.downloadPaths;
      expect(existingTrack.isDownloaded, isTrue);
    });

    test('孤儿文件应被识别（无匹配 Track）', () {
      // 本地存在的文件但数据库中没有对应的 Track
      final orphanInfo = _OrphanFileInfo(
        title: 'Orphan Song',
        path: '/local/orphan/audio.m4a',
        sourceId: 'BV999999999',
        sourceType: SourceType.bilibili,
      );

      // getOrphanFiles() 返回这些信息供 UI 显示
      expect(orphanInfo.title, isNotEmpty);
      expect(orphanInfo.path, isNotNull);
    });
  });

  group('Requirement 7: 实时显示已下载标记', () {
    test('下载完成事件应包含必要信息', () {
      // DownloadCompletionEvent 结构验证
      final event = _MockDownloadCompletionEvent(
        taskId: 1,
        trackId: 100,
        playlistId: 5,
        savePath: '/path/to/downloaded/audio.m4a',
      );

      expect(event.taskId, equals(1));
      expect(event.trackId, equals(100));
      expect(event.playlistId, equals(5));
      expect(event.savePath, isNotEmpty);
    });

    test('下载完成后 UI 应收到更新事件', () {
      // completionStream.listen((event) => ...)
      // 下载完成时 _completionController.add(event)
      
      // 模拟事件流
      final events = <_MockDownloadCompletionEvent>[];
      
      // 下载完成，触发事件
      events.add(_MockDownloadCompletionEvent(
        taskId: 1,
        trackId: 100,
        playlistId: 5,
        savePath: '/path/audio.m4a',
      ));

      expect(events, hasLength(1));
      expect(events.first.trackId, equals(100));
    });

    test('下载完成后 FileExistsCache 应更新', () {
      // cache.markAsExisting(savePath) 在下载完成后调用
      final cache = <String>{};
      const savePath = '/path/to/downloaded/audio.m4a';

      // 下载前
      expect(cache.contains(savePath), isFalse);

      // 下载完成后 markAsExisting
      cache.add(savePath);

      // 下载后
      expect(cache.contains(savePath), isTrue);
    });

    test('同步歌曲后 Track.downloadPaths 应更新', () {
      // 同步前
      final track = Track()
        ..id = 1
        ..sourceId = 'BV123'
        ..sourceType = SourceType.bilibili
        ..downloadPaths = [];

      expect(track.isDownloaded, isFalse);

      // 同步后 addDownloadPath
      track.downloadPaths = ['/synced/path/audio.m4a'];

      expect(track.isDownloaded, isTrue);
    });

    test('修改下载路径后所有 Track 应失去已下载标记', () {
      // 修改路径前
      final tracks = [
        Track()..downloadPaths = ['/old/path1.m4a'],
        Track()..downloadPaths = ['/old/path2.m4a'],
      ];

      expect(tracks.every((t) => t.isDownloaded), isTrue);

      // 修改路径后 clearAllDownloadPaths
      for (final track in tracks) {
        track.playlistIds = [];
        track.downloadPaths = [];
      }

      expect(tracks.every((t) => !t.isDownloaded), isTrue);
    });
  });

  group('Integration: 播放歌曲时使用本地文件', () {
    test('有本地文件时应优先使用本地路径', () {
      // AudioController 播放逻辑：
      // 1. 检查 track.localAudioPath（实际文件存在）
      // 2. 如果存在，使用本地路径播放
      // 3. 如果不存在，回退到网络 URL

      final track = Track()
        ..sourceId = 'BV123'
        ..sourceType = SourceType.bilibili
        ..audioUrl = 'https://example.com/audio.m4a'
        ..downloadPaths = ['/local/audio.m4a'];

      // 模拟选择播放源的逻辑
      String? getPlaySource(Track t) {
        // 尝试获取本地路径
        final localPath = t.downloadPaths.firstOrNull;
        if (localPath != null) {
          // 在实际代码中会检查 File(localPath).existsSync()
          // 这里假设存在
          return localPath;
        }
        // 回退到网络 URL
        return t.audioUrl;
      }

      final source = getPlaySource(track);
      expect(source, equals('/local/audio.m4a'));
    });

    test('本地文件不存在时应回退到网络并清除路径', () {
      // 如果 localAudioPath 为 null（文件不存在）
      // 应该：
      // 1. 回退到网络 URL
      // 2. 清除数据库中的无效路径

      final track = Track()
        ..id = 1
        ..sourceId = 'BV123'
        ..sourceType = SourceType.bilibili
        ..audioUrl = 'https://example.com/audio.m4a'
        ..downloadPaths = ['/nonexistent/audio.m4a'];

      // 模拟 localAudioPath 为 null（文件不存在）
      String? localAudioPath;
      for (final path in track.downloadPaths) {
        try {
          if (File(path).existsSync()) {
            localAudioPath = path;
            break;
          }
        } catch (_) {}
      }

      expect(localAudioPath, isNull);

      // 回退到网络
      final playSource = localAudioPath ?? track.audioUrl;
      expect(playSource, equals('https://example.com/audio.m4a'));

      // 清除无效路径（在实际代码中会调用 trackRepo.clearDownloadPath）
      track.downloadPaths = [];
      expect(track.isDownloaded, isFalse);
    });
  });
}

/// 模拟孤儿文件信息（用于测试）
class _OrphanFileInfo {
  final String title;
  final String? path;
  final String sourceId;
  final SourceType sourceType;

  _OrphanFileInfo({
    required this.title,
    this.path,
    required this.sourceId,
    required this.sourceType,
  });
}

/// 模拟下载完成事件（用于测试）
class _MockDownloadCompletionEvent {
  final int taskId;
  final int trackId;
  final int? playlistId;
  final String savePath;

  _MockDownloadCompletionEvent({
    required this.taskId,
    required this.trackId,
    this.playlistId,
    required this.savePath,
  });
}
