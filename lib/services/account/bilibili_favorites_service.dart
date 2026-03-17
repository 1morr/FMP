import 'package:dio/dio.dart';
import 'package:isar/isar.dart';

import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';
import '../../data/models/track.dart';
import '../../i18n/strings.g.dart';
import 'bilibili_account_service.dart';
import 'bilibili_auth_interceptor.dart';

/// Bilibili 收藏夾數據模型
class BilibiliFavFolder {
  final int id; // mlid（API 操作用這個）
  final String title;
  final int mediaCount;
  final String? coverUrl; // 收藏夾封面
  final bool isFavorited; // 當前視頻是否已在此收藏夾
  final bool isDefault; // 是否為默認收藏夾

  const BilibiliFavFolder({
    required this.id,
    required this.title,
    required this.mediaCount,
    this.coverUrl,
    this.isFavorited = false,
    this.isDefault = false,
  });
}

/// Bilibili 收藏夾操作服務
class BilibiliFavoritesService with Logging {
  final BilibiliAccountService _accountService;
  final Dio _dio;
  final Isar _isar;

  static const String _apiBase = 'https://api.bilibili.com';

  BilibiliFavoritesService({
    required BilibiliAccountService accountService,
    required Isar isar,
  })  : _accountService = accountService,
        _isar = isar,
        _dio = _createDio(accountService);

  static Dio _createDio(BilibiliAccountService accountService) {
    final dio = Dio(BaseOptions(
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
        'Referer': 'https://www.bilibili.com/',
        'Origin': 'https://www.bilibili.com',
        'Accept': 'application/json, text/plain, */*',
      },
      connectTimeout: AppConstants.networkConnectTimeout,
      receiveTimeout: AppConstants.networkReceiveTimeout,
    ));
    dio.interceptors.add(BilibiliAuthInterceptor(accountService));
    return dio;
  }

  /// 獲取用戶收藏夾列表（帶視頻已存在標記）
  ///
  /// [videoAid] 如果提供，每個收藏夾的 isFavorited 會標記該視頻是否已存在
  Future<List<BilibiliFavFolder>> getFavFolders({int? videoAid}) async {
    final mid = await _accountService.getUserMid();
    if (mid == null) {
      throw BilibiliFavoritesException(
        code: -101,
        message: t.remote.error.notLoggedIn,
      );
    }

    final allFolders = <BilibiliFavFolder>[];
    int page = 1;
    bool hasMore = true;

    while (hasMore) {
      final queryParams = <String, dynamic>{
        'up_mid': mid,
        'type': 2,
        'pn': page,
        'ps': 20,
      };
      if (videoAid != null) {
        queryParams['rid'] = videoAid;
      }

      final response = await _dio.get(
        '$_apiBase/x/v3/fav/folder/created/list',
        queryParameters: queryParams,
      );

      _checkResponse(response.data);

      final data = response.data['data'];
      final list = data['list'] as List? ?? [];

      if (page == 1) {
        logDebug('getFavFolders: videoAid=$videoAid, count=${data['count']}, '
            'first page folders=${list.length}');
      }

      for (final item in list) {
        allFolders.add(BilibiliFavFolder(
          id: item['id'] as int,
          title: item['title'] as String? ?? '',
          mediaCount: item['media_count'] as int? ?? 0,
          coverUrl: item['cover'] as String?,
          isFavorited: (item['fav_state'] as int? ?? 0) == 1,
          isDefault: page == 1 && item['id'] == data['default_folder_id'],
        ));
      }

      hasMore = data['has_more'] as bool? ?? false;
      page++;
    }

    return allFolders;
  }

  /// 新建收藏夾
  Future<BilibiliFavFolder> createFavFolder({
    required String title,
    String intro = '',
    bool isPrivate = false,
  }) async {
    final csrf = await _accountService.getCsrfToken();
    if (csrf == null) {
      throw BilibiliFavoritesException(
        code: -111,
        message: t.remote.error.csrfFailed,
      );
    }

    final response = await _dio.post(
      '$_apiBase/x/v3/fav/folder/add',
      data: {
        'title': title,
        'intro': intro,
        'privacy': isPrivate ? 1 : 0,
        'csrf': csrf,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );

    _checkResponse(response.data);

    final data = response.data['data'];
    logInfo('Created fav folder: id=${data['id']}, title=$title');

    return BilibiliFavFolder(
      id: data['id'] as int,
      title: data['title'] as String? ?? title,
      mediaCount: 0,
    );
  }

  /// 添加/移除視頻到收藏夾（原子操作）
  Future<void> updateVideoFavorites({
    required int videoAid,
    List<int> addFolderIds = const [],
    List<int> removeFolderIds = const [],
  }) async {
    final csrf = await _accountService.getCsrfToken();
    if (csrf == null) {
      throw BilibiliFavoritesException(
        code: -111,
        message: t.remote.error.csrfFailed,
      );
    }

    final response = await _dio.post(
      '$_apiBase/x/v3/fav/resource/deal',
      data: {
        'rid': videoAid,
        'type': 2,
        'add_media_ids': addFolderIds.join(','),
        'del_media_ids': removeFolderIds.join(','),
        'csrf': csrf,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );

    _checkResponse(response.data);
    logInfo('Updated favorites for aid=$videoAid, '
        'added=${addFolderIds.length}, removed=${removeFolderIds.length}');
  }

  /// 批量從收藏夾移除
  Future<void> batchRemoveFromFolder({
    required int folderId,
    required List<int> videoAids,
  }) async {
    final csrf = await _accountService.getCsrfToken();
    if (csrf == null) {
      throw BilibiliFavoritesException(
        code: -111,
        message: t.remote.error.csrfFailed,
      );
    }

    // resources 格式: "aid1:2,aid2:2" (type=2 表示視頻)
    final resources = videoAids.map((aid) => '$aid:2').join(',');

    final response = await _dio.post(
      '$_apiBase/x/v3/fav/resource/batch-del',
      data: {
        'media_id': folderId,
        'resources': resources,
        'csrf': csrf,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );

    _checkResponse(response.data);
    logInfo('Batch removed ${videoAids.length} videos from folder $folderId');
  }

  /// 獲取視頻的 aid（從 bvid）
  ///
  /// 優先從 Track.bilibiliAid 緩存讀取，
  /// 緩存未命中時調用 view API 並緩存回 Track
  Future<int> getVideoAid(Track track) async {
    // 優先使用緩存
    if (track.bilibiliAid != null) {
      return track.bilibiliAid!;
    }

    // 調用 view API 獲取 aid
    final response = await _dio.get(
      '$_apiBase/x/web-interface/view',
      queryParameters: {'bvid': track.sourceId},
    );

    _checkResponse(response.data);

    final aid = response.data['data']['aid'] as int;

    // 緩存回 Track（如果 track 已持久化）
    if (track.id > 0) {
      try {
        await _isar.writeTxn(() async {
          final saved = await _isar.tracks.get(track.id);
          if (saved != null) {
            saved.bilibiliAid = aid;
            await _isar.tracks.put(saved);
          }
        });
      } catch (e) {
        logWarning('Failed to cache bilibiliAid for track ${track.id}: $e');
      }
    }

    // 也更新傳入的 track 對象
    track.bilibiliAid = aid;
    return aid;
  }

  /// 檢查 API 響應
  void _checkResponse(Map<String, dynamic> data) {
    final code = data['code'] as int?;
    if (code != 0) {
      final message = data['message'] as String? ?? 'Unknown error';
      throw BilibiliFavoritesException(
        code: code ?? -999,
        message: _mapErrorMessage(code ?? -999, message),
      );
    }
  }

  /// 映射錯誤碼到用戶友好的消息
  String _mapErrorMessage(int code, String fallback) {
    switch (code) {
      case -101:
        return t.remote.error.notLoggedIn;
      case -111:
        return t.remote.error.csrfFailed;
      case -403:
        return t.remote.error.noPermission;
      case -607:
        return t.remote.error.favoritesLimit;
      case 11010:
        return t.remote.error.contentNotFound;
      case 11201:
        return t.remote.error.alreadyFavorited;
      default:
        return t.remote.error.unknown(code: code.toString());
    }
  }
}

/// Bilibili 收藏夾操作異常
class BilibiliFavoritesException implements Exception {
  final int code;
  final String message;

  const BilibiliFavoritesException({
    required this.code,
    required this.message,
  });

  /// 是否需要重新登錄
  bool get requiresLogin => code == -101 || code == -111;

  @override
  String toString() => 'BilibiliFavoritesException($code): $message';
}
