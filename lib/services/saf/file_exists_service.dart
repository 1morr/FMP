import 'dart:io';
import 'saf_service.dart';

/// Unified file existence detection service
///
/// Supports both standard file paths and Android SAF content:// URIs.
/// Provides async methods for file detection and batch operations.
class FileExistsService {
  final SafService _safService;

  FileExistsService(this._safService);

  /// Check if a file exists (async)
  ///
  /// Supports both file paths and content:// URIs.
  Future<bool> exists(String path) async {
    if (SafService.isContentUri(path)) {
      return _safService.exists(path);
    }
    return File(path).exists();
  }

  /// Check if a file exists (sync)
  ///
  /// Returns null for content:// URIs (cannot check synchronously).
  /// For such cases, use async [exists] instead.
  bool? existsSync(String path) {
    if (SafService.isContentUri(path)) {
      return null; // Cannot check synchronously
    }
    return File(path).existsSync();
  }

  /// Filter a list of paths to only those that exist
  Future<List<String>> filterExisting(List<String> paths) async {
    final results = <String>[];
    for (final path in paths) {
      if (await exists(path)) {
        results.add(path);
      }
    }
    return results;
  }

  /// Get the first path that exists from a list
  Future<String?> getFirstExisting(List<String> paths) async {
    for (final path in paths) {
      if (await exists(path)) {
        return path;
      }
    }
    return null;
  }

  /// Check multiple paths in parallel and return a map of results
  Future<Map<String, bool>> checkMultiple(List<String> paths) async {
    final futures = paths.map((path) async {
      return MapEntry(path, await exists(path));
    });
    final entries = await Future.wait(futures);
    return Map.fromEntries(entries);
  }
}
