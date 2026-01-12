/// 已下载分类（文件夹）数据模型
class DownloadedCategory {
  /// 原始文件夹名
  final String folderName;

  /// 显示名称（去掉 _id 后缀）
  final String displayName;

  /// 歌曲数量
  final int trackCount;

  /// 第一首歌的封面路径
  final String? coverPath;

  /// 完整文件夹路径
  final String folderPath;

  const DownloadedCategory({
    required this.folderName,
    required this.displayName,
    required this.trackCount,
    this.coverPath,
    required this.folderPath,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DownloadedCategory && other.folderPath == folderPath;
  }

  @override
  int get hashCode => folderPath.hashCode;
}
