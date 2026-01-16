import 'dart:io';

import '../../data/models/playlist.dart';

/// Playlist 模型扩展方法
extension PlaylistExtensions on Playlist {
  /// 获取本地封面路径（仅返回存在的文件）
  ///
  /// 检查预计算的 coverLocalPath 是否实际存在
  /// 如果不存在，返回 null
  String? get localCoverPath {
    if (coverLocalPath == null) return null;
    return File(coverLocalPath!).existsSync() ? coverLocalPath : null;
  }

  /// 是否有本地封面（文件实际存在）
  bool get hasLocalCover => localCoverPath != null;

  /// 是否有网络封面
  bool get hasNetworkCover => coverUrl != null && coverUrl!.isNotEmpty;

  /// 是否有任何封面（本地或网络）
  bool get hasCover => hasLocalCover || hasNetworkCover;
}
