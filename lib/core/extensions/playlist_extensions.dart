import '../../data/models/playlist.dart';
import '../../providers/download/file_exists_cache.dart';

/// Playlist 模型扩展方法
extension PlaylistExtensions on Playlist {
  /// 获取本地封面路径（使用缓存，适用于 UI 组件）
  ///
  /// 检查预计算的 coverLocalPath 是否实际存在
  /// 如果不存在，返回 null
  ///
  /// [cache] FileExistsCache 实例，从 ref.read(fileExistsCacheProvider.notifier) 获取
  String? getLocalCoverPath(FileExistsCache cache) {
    if (coverLocalPath == null) return null;
    return cache.exists(coverLocalPath!) ? coverLocalPath : null;
  }

  /// 是否有网络封面
  bool get hasNetworkCover => coverUrl != null && coverUrl!.isNotEmpty;
}
