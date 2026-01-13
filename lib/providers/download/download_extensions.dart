import '../../data/models/download_task.dart';
import '../../data/models/track.dart';
import '../../data/models/playlist.dart';
import '../../services/download/download_service.dart';

/// 扩展方法：为 Track 添加下载功能
extension TrackDownloadExtension on Track {
  /// 下载此歌曲
  /// 
  /// [fromPlaylist] 必须提供，歌曲必须属于某个歌单才能下载
  Future<DownloadTask?> download(
    DownloadService service, {
    required Playlist fromPlaylist,
  }) async {
    return service.addTrackDownload(this, fromPlaylist: fromPlaylist);
  }
}

/// 扩展方法：为 Playlist 添加下载功能
extension PlaylistDownloadExtension on Playlist {
  /// 下载整个歌单（以单曲形式）
  /// 返回添加的下载任务数量
  Future<int> download(DownloadService service) async {
    return service.addPlaylistDownload(this);
  }
}
