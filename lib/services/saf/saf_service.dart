import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

/// Information about a file or directory in SAF
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

  @override
  String toString() =>
      'SafFileInfo(name: $name, isDirectory: $isDirectory, size: $size)';
}

/// Storage Access Framework (SAF) service for Android
///
/// Provides methods to interact with Android's SAF system for accessing
/// user-selected directories via content:// URIs.
///
/// On Windows/other platforms, falls back to standard file operations.
class SafService {
  static const _channel = MethodChannel('com.fmp/saf');

  /// Check if a path is a content:// URI
  static bool isContentUri(String path) => path.startsWith('content://');

  /// Pick a directory using system UI
  ///
  /// Returns the directory path/URI, or null if cancelled.
  /// On Android, returns a content:// URI with persistent permissions.
  /// On Windows, returns a file system path.
  Future<String?> pickDirectory() async {
    // file_picker handles SAF on Android automatically
    return FilePicker.platform.getDirectoryPath();
  }

  /// Check if app has persisted permission for the URI
  Future<bool> hasPersistedPermission(String uri) async {
    if (!Platform.isAndroid) return true;
    if (!isContentUri(uri)) return true;

    try {
      return await _channel.invokeMethod('hasPersistedPermission', {'uri': uri});
    } catch (e) {
      return false;
    }
  }

  /// Get a human-readable display name for a directory URI
  ///
  /// Returns a path like "Music/FMP" from a content:// URI.
  Future<String> getDisplayName(String uri) async {
    if (!Platform.isAndroid || !isContentUri(uri)) {
      return uri;
    }

    try {
      return await _channel.invokeMethod('getDisplayName', {'uri': uri});
    } catch (e) {
      return uri;
    }
  }

  /// Check if a file or directory exists
  Future<bool> exists(String uri) async {
    if (!Platform.isAndroid || !isContentUri(uri)) {
      return File(uri).exists();
    }

    try {
      return await _channel.invokeMethod('exists', {'uri': uri});
    } catch (e) {
      return false;
    }
  }

  /// Get file size in bytes
  Future<int> getFileSize(String uri) async {
    if (!Platform.isAndroid || !isContentUri(uri)) {
      return await File(uri).length();
    }

    return await _channel.invokeMethod('getFileSize', {'uri': uri});
  }

  /// Read a byte range from a file
  ///
  /// Used for streaming audio playback without loading entire file into memory.
  Future<Uint8List> readRange(String uri, int start, int length) async {
    if (!Platform.isAndroid || !isContentUri(uri)) {
      final file = File(uri);
      final raf = await file.open();
      try {
        await raf.setPosition(start);
        return await raf.read(length);
      } finally {
        await raf.close();
      }
    }

    return await _channel.invokeMethod('readRange', {
      'uri': uri,
      'start': start,
      'length': length,
    });
  }

  /// Create a file in a directory
  ///
  /// [parentUri] must be a tree URI with write permissions.
  /// Returns the URI of the created file, or null on failure.
  Future<String?> createFile(
    String parentUri,
    String fileName, {
    String mimeType = 'audio/mp4',
  }) async {
    if (!Platform.isAndroid || !isContentUri(parentUri)) {
      final filePath = '$parentUri${Platform.pathSeparator}$fileName';
      final file = File(filePath);
      await file.parent.create(recursive: true);
      await file.create();
      return filePath;
    }

    try {
      return await _channel.invokeMethod('createFile', {
        'parentUri': parentUri,
        'fileName': fileName,
        'mimeType': mimeType,
      });
    } catch (e) {
      return null;
    }
  }

  /// Create a subdirectory
  ///
  /// [parentUri] must be a tree URI with write permissions.
  /// Returns the URI of the created directory, or null on failure.
  Future<String?> createDirectory(String parentUri, String dirName) async {
    if (!Platform.isAndroid || !isContentUri(parentUri)) {
      final dirPath = '$parentUri${Platform.pathSeparator}$dirName';
      await Directory(dirPath).create(recursive: true);
      return dirPath;
    }

    try {
      return await _channel.invokeMethod('createFile', {
        'parentUri': parentUri,
        'fileName': dirName,
        'mimeType': 'vnd.android.document/directory',
      });
    } catch (e) {
      return null;
    }
  }

  /// Write data to a file (overwrites existing content)
  Future<bool> writeToFile(String uri, Uint8List data) async {
    if (!Platform.isAndroid || !isContentUri(uri)) {
      await File(uri).writeAsBytes(data);
      return true;
    }

    try {
      return await _channel.invokeMethod('writeToFile', {
        'uri': uri,
        'data': data,
      });
    } catch (e) {
      return false;
    }
  }

  /// Append data to a file
  Future<bool> appendToFile(String uri, Uint8List data) async {
    if (!Platform.isAndroid || !isContentUri(uri)) {
      await File(uri).writeAsBytes(data, mode: FileMode.append);
      return true;
    }

    try {
      return await _channel.invokeMethod('appendToFile', {
        'uri': uri,
        'data': data,
      });
    } catch (e) {
      return false;
    }
  }

  /// Delete a file or directory
  Future<bool> deleteFile(String uri) async {
    if (!Platform.isAndroid || !isContentUri(uri)) {
      try {
        await File(uri).delete();
        return true;
      } catch (e) {
        return false;
      }
    }

    try {
      return await _channel.invokeMethod('deleteFile', {'uri': uri});
    } catch (e) {
      return false;
    }
  }

  /// List contents of a directory
  Future<List<SafFileInfo>> listDirectory(String uri) async {
    if (!Platform.isAndroid || !isContentUri(uri)) {
      final dir = Directory(uri);
      if (!await dir.exists()) {
        return [];
      }

      final entities = await dir.list().toList();
      return entities.map((e) {
        final stat = e.statSync();
        return SafFileInfo(
          uri: e.path,
          name: e.path.split(Platform.pathSeparator).last,
          isDirectory: e is Directory,
          size: stat.size,
        );
      }).toList();
    }

    try {
      final List<dynamic> result =
          await _channel.invokeMethod('listDirectory', {'uri': uri});
      return result
          .map((e) => SafFileInfo.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Find a file within a directory by name
  ///
  /// Returns the URI of the file if found, null otherwise.
  Future<String?> findFile(String directoryUri, String fileName) async {
    final files = await listDirectory(directoryUri);
    for (final file in files) {
      if (file.name == fileName) {
        return file.uri;
      }
    }
    return null;
  }

  /// Find or create a subdirectory
  ///
  /// Returns the URI of the existing or newly created directory.
  Future<String?> findOrCreateDirectory(
    String parentUri,
    String dirName,
  ) async {
    final contents = await listDirectory(parentUri);
    for (final item in contents) {
      if (item.isDirectory && item.name == dirName) {
        return item.uri;
      }
    }
    return createDirectory(parentUri, dirName);
  }
}
