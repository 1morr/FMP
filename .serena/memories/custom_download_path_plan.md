# 自定义下载路径实现计划

## 概述

实现用户自定义下载路径功能，支持 Android (SAF) 和 Windows 平台。

### 核心技术决策

| 平台 | 存储方案 | 路径格式 |
|------|----------|----------|
| **Android** | SAF (Storage Access Framework) | `content://` URI |
| **Windows** | 标准文件系统 | 文件路径 (如 `C:\Users\xxx\Music\FMP`) |

### 关键挑战

1. **Android Scoped Storage**: 从 Android 11 开始，无法直接写入公共目录
2. **just_audio 不支持 content:// URI**: 需要实现 `StreamAudioSource` 包装
3. **文件存在性检测**: `File.exists()` 不支持 content:// URI
4. **已下载页面扫描**: SAF 无法直接 list 目录内容

---

## Phase 1: 基础设施 - Platform Channel 和服务层

### 1.1 创建 Android Platform Channel

**文件**: `android/app/src/main/kotlin/com/fmp/SafMethodChannel.kt`

```kotlin
package com.fmp

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class SafMethodChannel(private val context: Context) : MethodChannel.MethodCallHandler {
    
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // 检测文件/目录是否存在
            "exists" -> handleExists(call, result)
            
            // 获取文件大小
            "getFileSize" -> handleGetFileSize(call, result)
            
            // 读取文件指定范围的字节
            "readRange" -> handleReadRange(call, result)
            
            // 在目录中创建文件
            "createFile" -> handleCreateFile(call, result)
            
            // 写入数据到文件
            "writeToFile" -> handleWriteToFile(call, result)
            
            // 追加数据到文件
            "appendToFile" -> handleAppendToFile(call, result)
            
            // 删除文件
            "deleteFile" -> handleDeleteFile(call, result)
            
            // 列出目录内容
            "listDirectory" -> handleListDirectory(call, result)
            
            // 获取持久化权限状态
            "hasPersistedPermission" -> handleHasPersistedPermission(call, result)
            
            // 获取目录显示名称
            "getDisplayName" -> handleGetDisplayName(call, result)
            
            else -> result.notImplemented()
        }
    }
    
    private fun handleExists(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")!!
        val uri = Uri.parse(uriString)
        try {
            val cursor = context.contentResolver.query(uri, null, null, null, null)
            val exists = cursor?.use { it.count > 0 } ?: false
            result.success(exists)
        } catch (e: Exception) {
            result.success(false)
        }
    }
    
    private fun handleGetFileSize(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")!!
        val uri = Uri.parse(uriString)
        try {
            val cursor = context.contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)
            cursor?.use {
                if (it.moveToFirst()) {
                    val sizeIndex = it.getColumnIndex(OpenableColumns.SIZE)
                    if (sizeIndex >= 0) {
                        result.success(it.getLong(sizeIndex))
                        return
                    }
                }
            }
            result.error("ERROR", "Cannot get file size", null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }
    
    private fun handleReadRange(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")!!
        val start = call.argument<Int>("start")!!.toLong()
        val length = call.argument<Int>("length")!!
        val uri = Uri.parse(uriString)
        
        try {
            context.contentResolver.openInputStream(uri)?.use { inputStream ->
                inputStream.skip(start)
                val buffer = ByteArray(length)
                val bytesRead = inputStream.read(buffer)
                if (bytesRead > 0) {
                    result.success(if (bytesRead == length) buffer else buffer.copyOf(bytesRead))
                } else {
                    result.success(ByteArray(0))
                }
            } ?: result.error("ERROR", "Cannot open input stream", null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }
    
    private fun handleCreateFile(call: MethodCall, result: MethodChannel.Result) {
        val parentUriString = call.argument<String>("parentUri")!!
        val fileName = call.argument<String>("fileName")!!
        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
        
        val parentUri = Uri.parse(parentUriString)
        try {
            val fileUri = DocumentsContract.createDocument(
                context.contentResolver,
                parentUri,
                mimeType,
                fileName
            )
            if (fileUri != null) {
                result.success(fileUri.toString())
            } else {
                result.error("ERROR", "Failed to create file", null)
            }
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }
    
    private fun handleWriteToFile(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")!!
        val data = call.argument<ByteArray>("data")!!
        val uri = Uri.parse(uriString)
        
        try {
            context.contentResolver.openOutputStream(uri, "wt")?.use { outputStream ->
                outputStream.write(data)
                result.success(true)
            } ?: result.error("ERROR", "Cannot open output stream", null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }
    
    private fun handleAppendToFile(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")!!
        val data = call.argument<ByteArray>("data")!!
        val uri = Uri.parse(uriString)
        
        try {
            context.contentResolver.openOutputStream(uri, "wa")?.use { outputStream ->
                outputStream.write(data)
                result.success(true)
            } ?: result.error("ERROR", "Cannot open output stream", null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }
    
    private fun handleDeleteFile(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")!!
        val uri = Uri.parse(uriString)
        
        try {
            val deleted = DocumentsContract.deleteDocument(context.contentResolver, uri)
            result.success(deleted)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }
    
    private fun handleListDirectory(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")!!
        val treeUri = Uri.parse(uriString)
        
        try {
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
                treeUri,
                DocumentsContract.getTreeDocumentId(treeUri)
            )
            
            val children = mutableListOf<Map<String, Any?>>()
            val cursor = context.contentResolver.query(
                childrenUri,
                arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                    DocumentsContract.Document.COLUMN_SIZE
                ),
                null, null, null
            )
            
            cursor?.use {
                while (it.moveToNext()) {
                    val docId = it.getString(0)
                    val name = it.getString(1)
                    val mimeType = it.getString(2)
                    val size = it.getLong(3)
                    val isDirectory = mimeType == DocumentsContract.Document.MIME_TYPE_DIR
                    
                    val childUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
                    
                    children.add(mapOf(
                        "uri" to childUri.toString(),
                        "name" to name,
                        "isDirectory" to isDirectory,
                        "size" to size,
                        "mimeType" to mimeType
                    ))
                }
            }
            
            result.success(children)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }
    
    private fun handleHasPersistedPermission(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")!!
        val uri = Uri.parse(uriString)
        
        val persistedUris = context.contentResolver.persistedUriPermissions
        val hasPermission = persistedUris.any { 
            it.uri == uri && it.isReadPermission && it.isWritePermission 
        }
        result.success(hasPermission)
    }
    
    private fun handleGetDisplayName(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")!!
        val uri = Uri.parse(uriString)
        
        try {
            // 对于 tree URI，尝试获取友好的路径名称
            val docId = DocumentsContract.getTreeDocumentId(uri)
            // docId 格式通常是 "primary:Music/FMP" 或 "XXXX-XXXX:Music/FMP"
            val displayPath = docId.substringAfter(":", docId)
            result.success(displayPath)
        } catch (e: Exception) {
            result.success(uriString)
        }
    }
}
```

### 1.2 注册 Platform Channel

**文件**: `android/app/src/main/kotlin/com/fmp/MainActivity.kt` (修改)

```kotlin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val SAF_CHANNEL = "com.fmp/saf"
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SAF_CHANNEL)
            .setMethodCallHandler(SafMethodChannel(applicationContext))
    }
}
```

### 1.3 创建 Dart 端 SAF 服务

**文件**: `lib/services/saf/saf_service.dart` (新建)

```dart
import 'dart:io';
import 'dart:typed_data';
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
    if (!Platform.isAndroid) {
      // Windows/其他平台使用 file_picker
      return FilePicker.platform.getDirectoryPath();
    }
    
    // Android 使用 file_picker，它会自动处理 SAF
    final result = await FilePicker.platform.getDirectoryPath();
    return result;
  }
  
  /// 检查是否有持久化权限
  Future<bool> hasPersistedPermission(String uri) async {
    if (!Platform.isAndroid) return true;
    return await _channel.invokeMethod('hasPersistedPermission', {'uri': uri});
  }
  
  /// 获取目录显示名称
  Future<String> getDisplayName(String uri) async {
    if (!Platform.isAndroid || !uri.startsWith('content://')) {
      return uri;
    }
    return await _channel.invokeMethod('getDisplayName', {'uri': uri});
  }
  
  /// 检查文件/目录是否存在
  Future<bool> exists(String uri) async {
    if (!Platform.isAndroid || !uri.startsWith('content://')) {
      return File(uri).exists();
    }
    return await _channel.invokeMethod('exists', {'uri': uri});
  }
  
  /// 获取文件大小
  Future<int> getFileSize(String uri) async {
    if (!Platform.isAndroid || !uri.startsWith('content://')) {
      return (await File(uri).length());
    }
    return await _channel.invokeMethod('getFileSize', {'uri': uri});
  }
  
  /// 读取文件指定范围
  Future<Uint8List> readRange(String uri, int start, int length) async {
    if (!Platform.isAndroid || !uri.startsWith('content://')) {
      final file = File(uri);
      final raf = await file.open();
      await raf.setPosition(start);
      final bytes = await raf.read(length);
      await raf.close();
      return bytes;
    }
    return await _channel.invokeMethod('readRange', {
      'uri': uri,
      'start': start,
      'length': length,
    });
  }
  
  /// 在目录中创建文件
  Future<String?> createFile(String parentUri, String fileName, {String mimeType = 'audio/mp4'}) async {
    if (!Platform.isAndroid || !parentUri.startsWith('content://')) {
      final filePath = '$parentUri/$fileName';
      await File(filePath).create(recursive: true);
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
    if (!Platform.isAndroid || !parentUri.startsWith('content://')) {
      final dirPath = '$parentUri/$dirName';
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
    if (!Platform.isAndroid || !uri.startsWith('content://')) {
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
    if (!Platform.isAndroid || !uri.startsWith('content://')) {
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
    if (!Platform.isAndroid || !uri.startsWith('content://')) {
      await File(uri).delete();
      return true;
    }
    return await _channel.invokeMethod('deleteFile', {'uri': uri});
  }
  
  /// 列出目录内容
  Future<List<SafFileInfo>> listDirectory(String uri) async {
    if (!Platform.isAndroid || !uri.startsWith('content://')) {
      final dir = Directory(uri);
      final entities = await dir.list().toList();
      return entities.map((e) => SafFileInfo(
        uri: e.path,
        name: e.path.split('/').last,
        isDirectory: e is Directory,
        size: e is File ? (e as File).lengthSync() : 0,
      )).toList();
    }
    
    final List<dynamic> result = await _channel.invokeMethod('listDirectory', {'uri': uri});
    return result.map((e) => SafFileInfo.fromMap(Map<String, dynamic>.from(e))).toList();
  }
  
  /// 判断路径是否为 content:// URI
  static bool isContentUri(String path) => path.startsWith('content://');
}
```

---

## Phase 2: 文件存在性检测服务

### 2.1 创建统一文件检测服务

**文件**: `lib/services/saf/file_exists_service.dart` (新建)

```dart
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
```

### 2.2 修改 FileExistsCache

**文件**: `lib/providers/download/file_exists_cache.dart` (修改)

主要修改：
1. 注入 `FileExistsService` 依赖
2. 使用统一服务替代 `File.exists()`
3. 处理 content:// URI 的异步特性

```dart
// 添加 provider
final fileExistsServiceProvider = Provider<FileExistsService>((ref) {
  return FileExistsService(SafService());
});

final fileExistsCacheProvider = StateNotifierProvider<FileExistsCache, Map<String, bool>>((ref) {
  final fileExistsService = ref.watch(fileExistsServiceProvider);
  return FileExistsCache(fileExistsService);
});
```

---

## Phase 3: SafAudioSource 实现

### 3.1 创建 SAF 音频源

**文件**: `lib/services/audio/saf_audio_source.dart` (新建)

```dart
import 'dart:async';
import 'dart:typed_data';
import 'package:just_audio/just_audio.dart';
import '../saf/saf_service.dart';

/// SAF 音频源
/// 
/// 用于播放 content:// URI 的音频文件
/// 通过 Platform Channel 实现 range request
class SafAudioSource extends StreamAudioSource {
  final String contentUri;
  final int fileSize;
  final SafService _safService;
  
  /// 缓冲块大小 (256KB)
  static const int _bufferSize = 256 * 1024;
  
  SafAudioSource({
    required this.contentUri,
    required this.fileSize,
    required SafService safService,
  }) : _safService = safService;
  
  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= fileSize;
    
    final length = end - start;
    
    // 读取指定范围的数据
    final bytes = await _safService.readRange(contentUri, start, length);
    
    return StreamAudioResponse(
      sourceLength: fileSize,
      contentLength: length,
      offset: start,
      stream: Stream.value(bytes),
      contentType: 'audio/mp4', // m4a 格式
    );
  }
  
  /// 创建 SafAudioSource（需要先获取文件大小）
  static Future<SafAudioSource> create(String contentUri, SafService safService) async {
    final fileSize = await safService.getFileSize(contentUri);
    return SafAudioSource(
      contentUri: contentUri,
      fileSize: fileSize,
      safService: safService,
    );
  }
}
```

### 3.2 修改 AudioService

**文件**: `lib/services/audio/audio_service.dart` (修改)

在 `_createFileAudioSource` 或新增方法中支持 content:// URI：

```dart
/// 创建音频源（支持普通路径和 content:// URI）
Future<AudioSource> _createAudioSource(String path, {Track? track}) async {
  if (SafService.isContentUri(path)) {
    // Android SAF content:// URI
    return SafAudioSource.create(path, _safService);
  } else {
    // 普通文件路径
    return _createFileAudioSource(path, track: track);
  }
}
```

---

## Phase 4: 下载服务修改

### 4.1 修改 DownloadService

**文件**: `lib/services/download/download_service.dart` (修改)

主要修改：
1. 注入 `SafService`
2. 下载时根据平台选择写入方式
3. 支持 content:// URI 的断点续传

```dart
Future<void> _startDownload(DownloadTask task) async {
  // ... 现有代码 ...
  
  // 确定保存路径
  final savePath = await _getDownloadPath(track, task);
  
  if (SafService.isContentUri(savePath)) {
    // Android SAF 写入
    await _downloadWithSaf(task, track, audioUrl, savePath);
  } else {
    // 普通文件写入（现有逻辑）
    await _downloadWithFile(task, track, audioUrl, savePath);
  }
}

/// SAF 写入方式下载
Future<void> _downloadWithSaf(
  DownloadTask task,
  Track track,
  String audioUrl,
  String directoryUri,
) async {
  // 1. 在目录中创建子目录（歌单名/视频文件夹）
  final playlistDir = await _safService.createDirectory(directoryUri, sanitizedPlaylistName);
  final videoDir = await _safService.createDirectory(playlistDir!, videoFolderName);
  
  // 2. 创建音频文件
  final audioFileUri = await _safService.createFile(videoDir!, audioFileName, mimeType: 'audio/mp4');
  
  // 3. 下载到临时文件，然后复制
  // 或直接分块写入 (需要服务器支持 range request)
  
  // 4. 保存元数据
  await _saveMetadataWithSaf(track, videoDir, videoDetail: videoDetail);
}
```

### 4.2 修改 DownloadPathUtils

**文件**: `lib/services/download/download_path_utils.dart` (修改)

```dart
/// 计算下载路径
/// 
/// Android: 返回目录的 content:// URI（实际文件 URI 在下载时创建）
/// Windows: 返回完整文件路径
static Future<String> computeDownloadPath({
  required SettingsRepository settingsRepo,
  required String playlistName,
  required String sourceId,
  required String title,
  required int partIndex,
  required int totalParts,
}) async {
  final baseDir = await getDefaultBaseDir(settingsRepo);
  
  if (SafService.isContentUri(baseDir)) {
    // Android SAF: 返回目录 URI，实际文件路径在下载时动态创建
    // 格式: content://xxx/tree/yyy::playlistName::sourceId_title::P01.m4a
    // 注意：这是一个虚拟路径格式，用于数据库存储和后续解析
    return '$baseDir::$playlistName::${sourceId}_${sanitizeFileName(title)}::${_formatPartIndex(partIndex, totalParts)}.m4a';
  }
  
  // Windows: 返回完整文件路径
  final dir = p.join(baseDir, sanitizeFileName(playlistName), '${sourceId}_${sanitizeFileName(title)}');
  final fileName = '${_formatPartIndex(partIndex, totalParts)}.m4a';
  return p.join(dir, fileName);
}

/// 获取默认基础目录
static Future<String> getDefaultBaseDir(SettingsRepository settingsRepo) async {
  final settings = await settingsRepo.get();

  // 1. 优先使用自定义目录
  if (settings.customDownloadDir != null && settings.customDownloadDir!.isNotEmpty) {
    return settings.customDownloadDir!;
  }

  // 2. Android: 返回 null（强制用户选择）
  if (Platform.isAndroid) {
    return ''; // 空字符串表示未设置
  }

  // 3. Windows/其他: Documents 目录
  final docsDir = await getApplicationDocumentsDirectory();
  return p.join(docsDir.path, 'FMP');
}
```

---

## Phase 5: 已下载页面重构

### 5.1 修改 DownloadScanner

**文件**: `lib/providers/download/download_scanner.dart` (修改)

需要支持扫描 content:// URI 目录：

```dart
/// 扫描已下载文件
Future<List<DownloadedCategory>> scanDownloads() async {
  final baseDir = await DownloadPathUtils.getDefaultBaseDir(_settingsRepo);
  
  if (baseDir.isEmpty) {
    return []; // 未设置下载目录
  }
  
  if (SafService.isContentUri(baseDir)) {
    return _scanWithSaf(baseDir);
  } else {
    return _scanWithFile(baseDir);
  }
}

/// 使用 SAF 扫描
Future<List<DownloadedCategory>> _scanWithSaf(String directoryUri) async {
  final categories = <DownloadedCategory>[];
  
  // 列出一级目录（歌单）
  final playlistDirs = await _safService.listDirectory(directoryUri);
  
  for (final playlistDir in playlistDirs.where((d) => d.isDirectory)) {
    // 列出二级目录（视频）
    final videoDirs = await _safService.listDirectory(playlistDir.uri);
    
    final tracks = <ScannedTrack>[];
    for (final videoDir in videoDirs.where((d) => d.isDirectory)) {
      // 查找 metadata.json 和音频文件
      final files = await _safService.listDirectory(videoDir.uri);
      // ... 解析并添加 track ...
    }
    
    categories.add(DownloadedCategory(
      name: playlistDir.name,
      path: playlistDir.uri,
      tracks: tracks,
    ));
  }
  
  return categories;
}
```

---

## Phase 6: Settings 模型和 UI

### 6.1 修改 Settings 模型

**文件**: `lib/data/models/settings.dart` (修改)

```dart
@collection
class Settings {
  // ... 现有字段 ...
  
  /// 下载目录
  /// - Windows: 文件路径
  /// - Android: content:// URI
  String? customDownloadDir;
  
  /// 下载目录显示名称（用于 UI）
  String? customDownloadDirDisplayName;
}
```

### 6.2 修改 Track Extensions

**文件**: `lib/core/extensions/track_extensions.dart` (修改)

```dart
extension TrackExtensions on Track {
  /// 获取本地音频路径（支持 content:// URI）
  /// 
  /// 注意：此方法现在返回 Future，因为 content:// URI 需要异步检测
  /// 对于同步场景，应使用 FileExistsCache
  Future<String?> getLocalAudioPath(FileExistsService fileService) async {
    if (downloadPaths.isEmpty) return null;
    
    for (final path in downloadPaths) {
      if (await fileService.exists(path)) {
        return path;
      }
    }
    return null;
  }
  
  /// 保留同步版本用于向后兼容（仅支持普通文件路径）
  @Deprecated('Use getLocalAudioPath with FileExistsService for content:// support')
  String? get localAudioPath {
    if (downloadPaths.isEmpty) return null;
    
    for (final path in downloadPaths) {
      if (!SafService.isContentUri(path) && File(path).existsSync()) {
        return path;
      }
    }
    return null;
  }
}
```

### 6.3 设置页面 UI

**文件**: `lib/ui/pages/settings/settings_page.dart` (修改)

添加下载目录选择 UI：

```dart
// 下载目录设置
ListTile(
  leading: const Icon(Icons.folder),
  title: const Text('下载目录'),
  subtitle: Text(
    settings.customDownloadDirDisplayName ?? 
    (Platform.isAndroid ? '未设置（点击选择）' : settings.customDownloadDir ?? '默认目录'),
  ),
  trailing: const Icon(Icons.chevron_right),
  onTap: () => _selectDownloadDirectory(context, ref),
),

// 如果 Android 未设置，显示警告
if (Platform.isAndroid && settings.customDownloadDir == null)
  Container(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.orange.withOpacity(0.1),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.orange.withOpacity(0.3)),
    ),
    child: Row(
      children: [
        Icon(Icons.warning_amber, color: Colors.orange),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            '请先选择下载目录，否则无法下载音乐',
            style: TextStyle(color: Colors.orange[800]),
          ),
        ),
      ],
    ),
  ),
```

---

## Phase 7: 测试检查清单

### 7.1 基础功能测试

- [ ] Android: SAF 目录选择正常弹出
- [ ] Android: 选择目录后 URI 正确保存
- [ ] Android: 重启 App 后权限仍有效
- [ ] Windows: 默认目录正常使用
- [ ] Windows: 自定义目录选择和保存

### 7.2 下载功能测试

- [ ] Android: 下载文件正确写入 SAF 目录
- [ ] Android: 下载进度正常显示
- [ ] Android: 断点续传正常工作
- [ ] Android: 元数据正确保存
- [ ] Windows: 下载功能不受影响

### 7.3 播放功能测试

- [ ] Android: SafAudioSource 正常播放
- [ ] Android: Seek 功能正常工作
- [ ] Android: 播放进度正确显示
- [ ] Windows: 播放功能不受影响

### 7.4 已下载检测测试

- [ ] Android: content:// URI 文件存在性正确检测
- [ ] Android: 歌单详情页已下载标记正确显示
- [ ] Android: 已下载页面正确扫描并显示
- [ ] Windows: 文件检测功能不受影响

### 7.5 边界情况测试

- [ ] 未设置目录时下载按钮正确提示
- [ ] SAF 权限被撤销后正确处理
- [ ] 用户选择无写入权限的目录
- [ ] 大文件下载和播放性能

---

## 文件变更汇总

### 新增文件

| 文件 | 说明 |
|------|------|
| `android/.../SafMethodChannel.kt` | Android Platform Channel |
| `lib/services/saf/saf_service.dart` | SAF 服务封装 |
| `lib/services/saf/file_exists_service.dart` | 统一文件检测服务 |
| `lib/services/audio/saf_audio_source.dart` | SAF 音频源 |

### 修改文件

| 文件 | 修改内容 |
|------|----------|
| `android/.../MainActivity.kt` | 注册 Platform Channel |
| `lib/data/models/settings.dart` | 添加 `customDownloadDirDisplayName` |
| `lib/providers/download/file_exists_cache.dart` | 支持 content:// URI |
| `lib/core/extensions/track_extensions.dart` | 异步版本 `getLocalAudioPath` |
| `lib/services/download/download_service.dart` | SAF 写入支持 |
| `lib/services/download/download_path_utils.dart` | content:// URI 路径计算 |
| `lib/services/audio/audio_service.dart` | SafAudioSource 支持 |
| `lib/providers/download/download_scanner.dart` | SAF 目录扫描 |
| `lib/ui/pages/settings/settings_page.dart` | 目录选择 UI |

---

## 实现顺序建议

1. **Week 1**: Phase 1 (Platform Channel) + Phase 2 (文件检测服务)
2. **Week 2**: Phase 3 (SafAudioSource) + 播放测试
3. **Week 3**: Phase 4 (下载服务修改) + 下载测试
4. **Week 4**: Phase 5 (已下载页面) + Phase 6 (UI) + 集成测试

---

## 回滚方案

如果 SAF 方案出现严重问题，可以快速回滚到 App-Specific 目录方案：

1. 修改 `getDefaultBaseDir()` 返回 App-Specific 路径
2. 禁用 SAF 相关代码路径
3. 已下载的 SAF 文件仍可通过 content:// URI 访问

```dart
// 回滚代码
static Future<String> getDefaultBaseDir(SettingsRepository settingsRepo) async {
  if (Platform.isAndroid) {
    // 回滚：使用 App-Specific 目录
    final extDir = await getExternalStorageDirectory();
    return p.join(extDir!.path, 'Music');
  }
  // Windows 保持不变
  final docsDir = await getApplicationDocumentsDirectory();
  return p.join(docsDir.path, 'FMP');
}
```
