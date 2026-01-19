import 'dart:io';
import 'saf_service.dart';

/// 统一文件存在性检测服务
/// 
/// 支持两种路径格式：
/// - 普通文件路径 (file://)
/// - SAF content:// URI
class FileExistsService {
  final SafService _safService;
  
  FileExistsService(this._safService);
  
  /// 异步检测文件是否存在
  Future<bool> exists(String path) async {
    if (SafService.isContentUri(path)) {
      return _safService.exists(path);
    }
    return File(path).exists();
  }
  
  /// 同步检测（仅支持普通路径）
  /// 
  /// 对于 content:// URI，返回 null 表示需要异步检测
  bool? existsSync(String path) {
    if (SafService.isContentUri(path)) {
      return null; // 无法同步检测
    }
    return File(path).existsSync();
  }
  
  /// 批量检测，返回存在的路径列表
  Future<List<String>> filterExisting(List<String> paths) async {
    final results = <String>[];
    for (final path in paths) {
      if (await exists(path)) {
        results.add(path);
      }
    }
    return results;
  }
  
  /// 获取第一个存在的路径
  Future<String?> getFirstExisting(List<String> paths) async {
    for (final path in paths) {
      if (await exists(path)) {
        return path;
      }
    }
    return null;
  }
}
