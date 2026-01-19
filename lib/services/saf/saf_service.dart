import 'dart:io';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

/// SAF 文件信息
class SafFileInfo {
  final String uri;
  final String name;
  final bool isDirectory;
  final int size;
  final String? mimeType;
  
  SafFileInfo({
    required this.uri,
    required this.name,
    required this.isDirectory,
    required this.size,
    this.mimeType,
  });
  
  factory SafFileInfo.fromMap(Map<String, dynamic> map) {
    return SafFileInfo(
      uri: map['uri'] as String,
      name: map['name'] as String,
      isDirectory: map['isDirectory'] as bool,
      size: (map['size'] as num).toInt(),
      mimeType: map['mimeType'] as String?,
    );
  }
}

/// SAF 服务 - 处理 Android Storage Access Framework 操作
class SafService {
  static const _channel = MethodChannel('com.fmp/saf');
  
  /// 选择目录（返回持久化 URI）
  Future<String?> pickDirectory() async {
    // Android 和 Windows 都使用 file_picker
    final result = await FilePicker.platform.getDirectoryPath();
    return result;
  }
  
  /// 检查是否有持久化权限
  Future<bool> hasPersistedPermission(String uri) async {
    if (!Platform.isAndroid) return true;
    if (!isContentUri(uri)) return true;
    return await _channel.invokeMethod('hasPersistedPermission', {'uri': uri});
  }
  
  /// 获取目录显示名称
  Future<String> getDisplayName(String uri) async {
    if (!Platform.isAndroid || !isContentUri(uri)) {
      return uri;
    }
    return await _channel.invokeMethod('getDisplayName', {'uri': uri});
  }
  
  /// 检查文件/目录是否存在
  Future<bool> exists(String uri) async {
    if (!Platform.isAndroid || !isContentUri(uri)) {
      return File(uri).exists();
    }
    return await _channel.invokeMethod('exists', {'uri': uri});
  }
  
  /// 获取文件大小
  Future<int> getFileSize(String uri) async {
    if (!Platform.isAndroid || !isContentUri(uri)) {
      return (await File(uri).length());
    }
    return await _channel.invokeMethod('getFileSize', {'uri': uri});
  }
  
  /// 读取文件指定范围
  Future<Uint8List> readRange(String uri, int start, int length) async {
    if (!Platform.isAndroid || !isContentUri(uri)) {
      final file = File(uri);
      final raf = await file.open();
      try {
        await raf.setPosition(start);
        final bytes = await raf.read(length);
        return bytes;
      } finally {
        await raf.close();
      }
    }
    final result = await _channel.invokeMethod<Uint8List>('readRange', {
      'uri': uri,
      'start': start,
      'length': length,
    });
    return result ?? Uint8List(0);
  }
  
  /// 在目录中创建文件
  Future<String?> createFile(String parentUri, String fileName, {String mimeType = 'audio/mp4'}) async {
    if (!Platform.isAndroid || !isContentUri(parentUri)) {
      final filePath = '$parentUri${Platform.pathSeparator}$fileName';
      final file = File(filePath);
      await file.parent.create(recursive: true);
      await file.create();
      return filePath;
    }
    return await _channel.invokeMethod('createFile', {
      'parentUri': parentUri,
      'fileName': fileName,
      'mimeType': mimeType,
    });
  }
  
  /// 创建子目录
  Future<String?> createDirectory(String parentUri, String dirName) async {
    if (!Platform.isAndroid || !isContentUri(parentUri)) {
      final dirPath = '$parentUri${Platform.pathSeparator}$dirName';
      await Directory(dirPath).create(recursive: true);
      return dirPath;
    }
    return await _channel.invokeMethod('createFile', {
      'parentUri': parentUri,
      'fileName': dirName,
      'mimeType': 'vnd.android.document/directory',
    });
  }
  
  /// 写入数据到文件
  Future<bool> writeToFile(String uri, Uint8List data) async {
    if (!Platform.isAndroid || !isContentUri(uri)) {
      await File(uri).writeAsBytes(data);
      return true;
    }
    return await _channel.invokeMethod('writeToFile', {
      'uri': uri,
      'data': data,
    });
  }
  
  /// 追加数据到文件
  Future<bool> appendToFile(String uri, Uint8List data) async {
    if (!Platform.isAndroid || !isContentUri(uri)) {
      await File(uri).writeAsBytes(data, mode: FileMode.append);
      return true;
    }
    return await _channel.invokeMethod('appendToFile', {
      'uri': uri,
      'data': data,
    });
  }
  
  /// 删除文件
  Future<bool> deleteFile(String uri) async {
    if (!Platform.isAndroid || !isContentUri(uri)) {
      await File(uri).delete();
      return true;
    }
    return await _channel.invokeMethod('deleteFile', {'uri': uri});
  }
  
  /// 列出目录内容
  Future<List<SafFileInfo>> listDirectory(String uri) async {
    if (!Platform.isAndroid || !isContentUri(uri)) {
      final dir = Directory(uri);
      final entities = await dir.list().toList();
      return await Future.wait(entities.map((e) async => SafFileInfo(
        uri: e.path,
        name: e.path.split(Platform.pathSeparator).last,
        isDirectory: e is Directory,
        size: e is File ? await e.length() : 0,
      )));
    }
    
    final List<dynamic> result = await _channel.invokeMethod('listDirectory', {'uri': uri});
    return result.map((e) => SafFileInfo.fromMap(Map<String, dynamic>.from(e))).toList();
  }
  
  /// 根据树 URI 和 document ID 构建文档 URI
  Future<String?> buildDocumentUri(String treeUri, String documentId) async {
    if (!Platform.isAndroid || !isContentUri(treeUri)) {
      return '$treeUri${Platform.pathSeparator}$documentId';
    }
    return await _channel.invokeMethod('buildDocumentUri', {
      'treeUri': treeUri,
      'documentId': documentId,
    });
  }
  
  /// 判断路径是否为 content:// URI
  static bool isContentUri(String path) => path.startsWith('content://');
}
