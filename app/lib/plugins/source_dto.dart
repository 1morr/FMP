import 'package:flutter/foundation.dart';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/network/allowed_hosts.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/domain/stream_preferences.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/plugins/accounts/login_credentials.dart';
import 'package:fmp/core/json_shape.dart';
import 'package:fmp/plugins/runtime/script_errors.dart';

// 宿主與插件交換的 DTO，apiVersion 1（ADR 0014 §決定 5）。
//
// 送給插件的（SearchQuery、StreamRequest）在建構時檢查參數，錯了是 App 的 bug，
// 拋 ArgumentError；插件回傳的（SearchPage、StreamResult）以 fromJson 解碼，
// 形狀不對拋 FormatException，由 ScriptSourcePlugin 轉成 ParseError。
//
// 欄位名稱是插件的介面：改名或改必填就是不相容的改動，要加 hostApiVersion。
// `lib/plugins/types/fmp-plugin.d.ts` 的同名 interface 與 [sourceDtoShapes]
// 由 test/plugins/type_definitions_test.dart 比對。

/// DTO 的欄位表，鍵是 `fmp-plugin.d.ts` 裡的 interface 名稱。
const sourceDtoShapes = <String, JsonShape>{
  'SearchQuery': {'keyword': true, 'page': true},
  'SearchPage': {'items': true, 'hasMore': true},
  'TrackSummary': {
    'sourceId': true,
    'cid': false,
    'title': true,
    'uploader': false,
    'durationMs': false,
    'artwork': false,
    'partCount': false,
    'partIndex': false,
    'parentTitle': false,
    'viewCount': false,
  },
  'Artwork': {'url': true, 'width': false},
  'StreamRequest': {
    'sourceId': true,
    'cid': false,
    'purpose': true,
    'formats': true,
    'quality': false,
  },
  'StreamFormat': {'container': true, 'codec': true},
  'StreamResult': {'candidates': true, 'previewOnly': false},
  'StreamCandidate': {
    'url': true,
    'headers': false,
    'container': false,
    'codec': false,
    'bitrate': false,
    'expiresAt': false,
  },
  'LoginQrCode': {'qrText': true, 'token': true},
  'LoginQrPoll': {'status': true, 'credentials': false},
  'LoginAccount': {'userId': true, 'displayName': true, 'avatar': false},
  'LiveSearchQuery': {'keyword': true, 'page': true, 'status': false},
  'LiveSearchPage': {'items': true, 'hasMore': true},
  'LiveRoom': {
    'roomId': true,
    'title': true,
    'hostName': false,
    'artwork': false,
    'status': true,
    'online': false,
    'area': false,
  },
  'LiveRoomQuery': {'roomId': true},
  'LiveUrlQuery': {'url': true},
  'LiveRoomRef': {'roomId': true},
  'LiveStreamRequest': {'roomId': true, 'formats': true},
  'MixSeedQuery': {'seed': true},
  'MixSeed': {'sourceId': true, 'cid': false},
  'MixContinueQuery': {'mixId': true, 'cursor': true},
  'MixBatch': {'mixId': true, 'title': true, 'tracks': true, 'cursor': false},
  'MultiPartQuery': {'sourceId': true},
  'MultiPartResult': {'parts': true},
  'MultiPartItem': {
    'cid': true,
    'title': true,
    'durationMs': false,
    'index': true,
  },
  'TrackDetailQuery': {'sourceId': true, 'cid': false},
  'TrackDetail': {
    'description': false,
    'publishedAt': false,
    'uploaderAvatar': false,
    'album': false,
    'stats': false,
    'webUrl': false,
  },
  'TrackStat': {'kind': true, 'count': true},
  'PlaylistUrlQuery': {'url': true},
  'PlaylistIdRef': {'playlistId': true},
  'PlaylistMixSeedRef': {'mixSeed': true},
  'PlaylistPageQuery': {'playlistId': true, 'cursor': false},
  'PlaylistPage': {
    'playlist': true,
    'items': true,
    'cursor': false,
    'total': false,
    'truncated': false,
  },
  'RemotePlaylist': {
    'title': true,
    'description': false,
    'artwork': false,
    'ownerName': false,
    'writable': false,
  },
  'RemotePlaylistItem': {
    'track': true,
    'remoteItemId': false,
    'unavailable': false,
  },
  'ChartList': {'charts': true},
  'ChartRef': {'chartId': true, 'title': true},
  'ChartQuery': {'chartId': true},
  'ChartPage': {'tracks': true},
  'LibraryPlaylistsQuery': {'cursor': false},
  'LibraryPlaylistPage': {'playlists': true, 'cursor': false},
  'LibraryLiveRooms': {'rooms': true},
  'LibraryPlaylist': {
    'playlistId': true,
    'title': true,
    'artwork': false,
    'trackCount': false,
    'writable': true,
  },
  'CreatePlaylistQuery': {'title': true},
  'CreatePlaylistResult': {'playlistId': true},
  'AddTrackRef': {'sourceId': true, 'cid': false},
  'AddToPlaylistQuery': {'playlistId': true, 'tracks': true},
  'AddToPlaylistResponse': {'results': true},
  'AddToPlaylistResult': {'status': true, 'error': false},
  'RemoveItemRef': {'sourceId': true, 'cid': false, 'remoteItemId': false},
  'RemoveFromPlaylistQuery': {'playlistId': true, 'items': true},
  'RemoveFromPlaylistResponse': {'results': true},
  'RemoveFromPlaylistResult': {'status': true, 'error': false},
  // 結構化錯誤（`throw {fmpError: …}`）的形狀，`results[].error` 也用它。
  'FmpError': {
    'fmpError': true,
    'retryAfterSeconds': false,
    'reason': false,
    'message': false,
  },
};

/// 搜尋的輸入。
@immutable
final class SearchQuery {
  SearchQuery({required this.keyword, this.page = 1}) {
    if (keyword.trim().isEmpty) {
      throw ArgumentError.value(keyword, 'keyword', 'must not be empty');
    }
    RangeError.checkValueInInterval(page, 1, 1 << 31, 'page');
  }

  final String keyword;

  /// 從 1 開始。
  final int page;

  Map<String, Object?> toJson() => {'keyword': keyword, 'page': page};
}

/// 搜尋的一頁結果。
@immutable
final class SearchPage {
  const SearchPage({required this.items, required this.hasMore});

  /// 解碼插件回傳的值。[sourceTypeId] 是插件 id：曲目鍵的第一段由宿主填，
  /// 插件不能宣稱別的音源的曲目。
  factory SearchPage.fromJson(
    Object? json, {
    required String sourceTypeId,
    required AllowedHosts allowedHosts,
  }) {
    final fields = JsonFields(
      json,
      sourceDtoShapes['SearchPage']!,
      path: 'SearchPage',
    );
    final hasMore = fields.optionalBool('hasMore');
    return SearchPage(
      items: List.unmodifiable([
        for (final (index, item) in fields.list('items').indexed)
          TrackSummary._fromJson(
            item,
            sourceTypeId: sourceTypeId,
            allowedHosts: allowedHosts,
            path: 'SearchPage.items[$index]',
          ),
      ]),
      hasMore:
          hasMore ??
          (throw const FormatException('SearchPage.hasMore: missing')),
    );
  }

  final List<TrackSummary> items;
  final bool hasMore;
}

/// 搜尋結果、歌單裡的一首曲目。
@immutable
final class TrackSummary {
  const TrackSummary({
    required this.sourceTypeId,
    required this.sourceId,
    this.cid,
    required this.title,
    this.uploader,
    this.duration,
    this.artwork = const [],
    this.partCount,
    this.partIndex,
    this.parentTitle,
    this.viewCount,
  }) : assert(
         (partIndex == null) == (parentTitle == null),
         'partIndex and parentTitle come together',
       );

  factory TrackSummary._fromJson(
    Object? json, {
    required String sourceTypeId,
    required AllowedHosts allowedHosts,
    required String path,
  }) {
    final fields = JsonFields(
      json,
      sourceDtoShapes['TrackSummary']!,
      path: path,
    );
    final durationMs = fields.optionalInteger('durationMs');
    final partIndex = fields.optionalInteger('partIndex', min: 1);
    final parentTitle = fields.optionalString('parentTitle');
    if (parentTitle != null && parentTitle.trim().isEmpty) {
      throw FormatException('$path.parentTitle: must not be empty');
    }
    // 兩欄一起給：只給一個，宿主寫進 TrackInfo 會顯示成半個分 P。
    if ((partIndex == null) != (parentTitle == null)) {
      throw FormatException(
        '$path: partIndex and parentTitle must be given together',
      );
    }
    return TrackSummary(
      sourceTypeId: sourceTypeId,
      sourceId: _sourceId(fields, path),
      cid: fields.optionalInteger('cid'),
      title: fields.nonEmptyString('title'),
      uploader: fields.optionalString('uploader'),
      duration: durationMs == null ? null : Duration(milliseconds: durationMs),
      artwork: List.unmodifiable([
        for (final (index, item)
            in (fields.optionalList('artwork') ?? []).indexed)
          Artwork._fromJson(
            item,
            allowedHosts: allowedHosts,
            path: '$path.artwork[$index]',
          ),
      ]),
      partCount: fields.optionalInteger('partCount', min: 1),
      partIndex: partIndex,
      parentTitle: parentTitle,
      viewCount: fields.optionalInteger('viewCount'),
    );
  }

  /// 曲目鍵的三段（`TrackKey.format`）：音源（插件 id）、音源內的 id、分 P 的 cid。
  final String sourceTypeId;
  final String sourceId;
  final int? cid;

  final String title;
  final String? uploader;
  final Duration? duration;

  /// 多尺寸封面（ADR 0016 §決定 4）；宿主挑最接近顯示尺寸的一張。
  final List<Artwork> artwork;

  /// 搜尋結果知道的分 P 數（ADR 0028 §決定 5），只是提示：空是不知道（展開鈕照顯示），
  /// 1 是確定單 P（不顯示）。只在記憶體，不存。
  final int? partCount;

  /// 分 P 曲目的序號（從 1 起）與影片標題（ADR 0032 §決定 1）：兩個一起給或一起沒有，
  /// 宿主寫進 [TrackInfo.partIndex]、[TrackInfo.parentTitle]。
  final int? partIndex;
  final String? parentTitle;

  /// 播放數（非負整數；ADR 0035 §決定 10）。選填：沒有就是不知道，曲目列不顯示。
  final int? viewCount;

  /// 插件以外（佇列、歷史）用的曲目：欄位逐一照搬。
  TrackInfo toTrackInfo() => TrackInfo(
    sourceTypeId: sourceTypeId,
    sourceId: sourceId,
    cid: cid,
    title: title,
    uploader: uploader,
    duration: duration,
    artwork: List.unmodifiable([
      for (final image in artwork)
        TrackArtwork(url: image.url, width: image.width),
    ]),
    partIndex: partIndex,
    parentTitle: parentTitle,
    viewCount: viewCount,
  );
}

/// 封面的一個尺寸。
@immutable
final class Artwork {
  const Artwork({required this.url, this.width});

  factory Artwork._fromJson(
    Object? json, {
    required AllowedHosts allowedHosts,
    required String path,
  }) {
    final fields = JsonFields(json, sourceDtoShapes['Artwork']!, path: path);
    final url = Uri.tryParse(fields.string('url'));
    if (url == null || !allowedHosts.allows(url)) {
      throw FormatException(
        '$path.url: must be an https URL on an allowed host',
      );
    }
    return Artwork(url: url, width: fields.optionalInteger('width', min: 1));
  }

  final Uri url;

  /// 像素寬度；不知道就是 `null`。
  final int? width;
}

/// 解析串流的用途（ADR 0014 §決定 5）。下載（ADR 0020）在 M6 加。
enum StreamPurpose {
  playback;

  String get wireName => switch (this) {
    playback => 'playback',
  };
}

/// 平台能播的一種格式（ADR 0018 §決定 6）：插件依它挑候選。值是小寫的慣用
/// 名稱（容器 `mp4`、`webm`，編碼 `aac`、`opus`）。
@immutable
final class StreamFormat {
  StreamFormat({required this.container, required this.codec}) {
    if (container.isEmpty || codec.isEmpty) {
      throw ArgumentError('container and codec must not be empty');
    }
  }

  final String container;
  final String codec;

  Map<String, Object?> toJson() => {'container': container, 'codec': codec};
}

/// [AudioQuality] 在插件介面上的名稱（`fmp-plugin.d.ts` 的 `FmpAudioQuality`）。
String audioQualityWireName(AudioQuality quality) => switch (quality) {
  AudioQuality.high => 'high',
  AudioQuality.medium => 'medium',
  AudioQuality.low => 'low',
};

/// `resolveStream` 的輸入。
@immutable
final class StreamRequest {
  StreamRequest({
    required this.sourceId,
    this.cid,
    required this.formats,
    this.purpose = StreamPurpose.playback,
    this.quality,
  }) {
    if (sourceId.isEmpty || sourceId.contains(':')) {
      throw ArgumentError.value(sourceId, 'sourceId', 'empty or contains ":"');
    }
    if (formats.isEmpty) {
      throw ArgumentError.value(formats, 'formats', 'must not be empty');
    }
  }

  /// 曲目鍵的第二、三段；第一段就是被呼叫的插件。
  final String sourceId;
  final int? cid;

  /// 平台能播的格式，依使用者的格式偏好排過（ADR 0018 §決定 6、design §7.4）。
  final List<StreamFormat> formats;
  final StreamPurpose purpose;

  /// 使用者的音質偏好；插件依它挑串流，沒給時由插件決定（插件 API v1 的選填
  /// 欄位，ADR 0014 §決定 5 的補充）。
  final AudioQuality? quality;

  Map<String, Object?> toJson() => {
    'sourceId': sourceId,
    'cid': ?cid,
    'purpose': purpose.wireName,
    'formats': [for (final format in formats) format.toJson()],
    if (quality case final quality?) 'quality': audioQualityWireName(quality),
  };
}

/// `resolveStream` 的回傳值：依優先序排好的候選（ADR 0018 §決定 6），至少一個。
@immutable
final class StreamResult {
  StreamResult({required this.candidates, this.previewOnly = false})
    : assert(candidates.isNotEmpty);

  /// 解碼插件回傳的 `{candidates: [...], previewOnly?}`。
  factory StreamResult.fromJson(
    Object? json, {
    required AllowedHosts allowedHosts,
  }) {
    final fields = JsonFields(
      json,
      sourceDtoShapes['StreamResult']!,
      path: 'StreamResult',
    );
    final candidates = fields.list('candidates');
    if (candidates.isEmpty) {
      throw const FormatException(
        'StreamResult.candidates: must not be empty; throw NotFound or '
        'Unavailable instead',
      );
    }
    return StreamResult(
      candidates: List.unmodifiable([
        for (final (index, item) in candidates.indexed)
          StreamCandidate._fromJson(
            item,
            allowedHosts: allowedHosts,
            path: 'StreamResult.candidates[$index]',
          ),
      ]),
      previewOnly: fields.optionalBool('previewOnly') ?? false,
    );
  }

  final List<StreamCandidate> candidates;

  /// 候選只有試聽片段（例如網易的非會員）：可以播，但不是整首。宿主依「跳過
  /// 試聽片段」設定跳過或標「試聽」後播放（ADR 0018 §決定 7、D4）。插件 API v1
  /// 的選填欄位，沒給就是 `false`。
  final bool previewOnly;
}

/// 一個候選串流。
@immutable
final class StreamCandidate {
  const StreamCandidate({
    required this.url,
    this.headers = const {},
    this.container,
    this.codec,
    this.bitrate,
    this.expiresAt,
  });

  factory StreamCandidate._fromJson(
    Object? json, {
    required AllowedHosts allowedHosts,
    required String path,
  }) {
    final fields = JsonFields(
      json,
      sourceDtoShapes['StreamCandidate']!,
      path: path,
    );
    final url = Uri.tryParse(fields.string('url'));
    if (url == null || !(allowedHosts.allows(url) || _isAsset(url))) {
      throw FormatException(
        '$path.url: must be an https URL on an allowed host or an asset URL',
      );
    }
    final expiresAt = fields.optionalInteger('expiresAt');
    // DateTime 只放得下 ±8.64e15 毫秒，超過會拋 RangeError 而不是 FormatException。
    if (expiresAt != null && expiresAt > _maxEpochMilliseconds) {
      throw FormatException('$path.expiresAt: out of range');
    }
    return StreamCandidate(
      url: url,
      headers: Map.unmodifiable(fields.optionalStringMap('headers') ?? {}),
      container: fields.optionalString('container'),
      codec: fields.optionalString('codec'),
      bitrate: fields.optionalInteger('bitrate'),
      expiresAt: expiresAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(expiresAt, isUtc: true),
    );
  }

  /// `https` 網址（網域在 manifest 的允許清單內），或 App 內附的 asset
  /// （`asset:///…`，測試插件用；不經網路）。
  final Uri url;

  /// 播放請求要帶的 headers；交給播放後端前先經 `mediaRequestHeaders`。
  final Map<String, String> headers;
  final String? container;
  final String? codec;

  /// 每秒位元數。
  final int? bitrate;

  /// 網址的期限，插件從網址本身讀（ADR 0016 §決定 5）；不知道就是 `null`。
  final DateTime? expiresAt;

  /// `asset:///<asset 鍵>`：沒有 host、userinfo、port。
  static bool _isAsset(Uri url) =>
      url.scheme == 'asset' &&
      url.host.isEmpty &&
      url.userInfo.isEmpty &&
      !url.hasPort &&
      url.path.length > 1;
}

/// `DateTime` 能表示的最大 epoch 毫秒（ECMAScript 的時間值範圍）。
const _maxEpochMilliseconds = 8640000000000000;

String _sourceId(JsonFields fields, String path) {
  final sourceId = fields.string('sourceId');
  if (sourceId.isEmpty || sourceId.contains(':')) {
    throw FormatException('$path.sourceId: empty or contains ":"');
  }
  return sourceId;
}

/// `loginQrStart` 的回傳值（ADR 0029 §決定 2）。
@immutable
final class LoginQrCode {
  const LoginQrCode({required this.qrText, required this.token});

  factory LoginQrCode.fromJson(Object? json) {
    final fields = JsonFields(
      json,
      sourceDtoShapes['LoginQrCode']!,
      path: 'LoginQrCode',
    );
    return LoginQrCode(
      qrText: fields.nonEmptyString('qrText'),
      token: fields.nonEmptyString('token'),
    );
  }

  /// 畫成 QR 碼的文字。
  final String qrText;

  /// 交給 `loginQrPoll` 的不透明字串。
  final String token;
}

/// QR 登入的進度（`fmp-plugin.d.ts` 的 `LoginQrStatus`）。
enum LoginQrStatus {
  waiting,
  scanned,
  expired,
  done;

  /// 插件介面上的名稱，與 [name] 分開寫死。
  String get wireName => switch (this) {
    waiting => 'waiting',
    scanned => 'scanned',
    expired => 'expired',
    done => 'done',
  };
}

/// `loginQrPoll` 的回傳值。
@immutable
final class LoginQrPoll {
  const LoginQrPoll(this.status, {this.credentials})
    : assert((status == LoginQrStatus.done) == (credentials != null));

  /// [LoginQrStatus.done] 一定帶憑證，其他狀態不能帶。
  factory LoginQrPoll.fromJson(Object? json) {
    const path = 'LoginQrPoll';
    final fields = JsonFields(json, sourceDtoShapes[path]!, path: path);
    final name = fields.string('status');
    final status = LoginQrStatus.values.firstWhere(
      (value) => value.wireName == name,
      orElse: () => throw FormatException('$path.status: unknown "$name"'),
    );
    final credentials = fields.raw('credentials');
    if ((status == LoginQrStatus.done) != (credentials != null)) {
      throw const FormatException(
        '$path.credentials: required exactly when the status is "done"',
      );
    }
    return LoginQrPoll(
      status,
      credentials: credentials == null
          ? null
          : LoginCredentials.fromJson(credentials),
    );
  }

  final LoginQrStatus status;
  final LoginCredentials? credentials;
}

/// `loginVerify` 的回傳值：憑證屬於哪個帳號（ADR 0012 §決定 4）。
@immutable
final class LoginAccount {
  const LoginAccount({
    required this.userId,
    required this.displayName,
    this.avatar = const [],
  });

  factory LoginAccount.fromJson(
    Object? json, {
    required AllowedHosts allowedHosts,
  }) {
    const path = 'LoginAccount';
    final fields = JsonFields(json, sourceDtoShapes[path]!, path: path);
    return LoginAccount(
      userId: fields.nonEmptyString('userId'),
      displayName: fields.nonEmptyString('displayName'),
      avatar: List.unmodifiable([
        for (final (index, item)
            in (fields.optionalList('avatar') ?? []).indexed)
          Artwork._fromJson(
            item,
            allowedHosts: allowedHosts,
            path: '$path.avatar[$index]',
          ),
      ]),
    );
  }

  final String userId;
  final String displayName;

  /// 多尺寸頭像；沒有就是空的。
  final List<Artwork> avatar;
}

/// 直播間的狀態（`fmp-plugin.d.ts` 的 `LiveRoomStatus`）。
enum LiveRoomStatus {
  live,
  offline;

  /// 插件介面上的名稱，與 [name] 分開寫死。
  String get wireName => switch (this) {
    live => 'live',
    offline => 'offline',
  };

  static LiveRoomStatus? fromWireName(String name) {
    for (final status in values) {
      if (status.wireName == name) return status;
    }
    return null;
  }
}

/// `liveSearch` 的輸入（ADR 0028 §決定 3）。
@immutable
final class LiveSearchQuery {
  LiveSearchQuery({required this.keyword, this.page = 1, this.status}) {
    if (keyword.trim().isEmpty) {
      throw ArgumentError.value(keyword, 'keyword', 'must not be empty');
    }
    RangeError.checkValueInInterval(page, 1, 1 << 31, 'page');
  }

  final String keyword;

  /// 從 1 開始。
  final int page;

  /// 「開播中／未開播」篩選；`null` 是全部。
  final LiveRoomStatus? status;

  Map<String, Object?> toJson() => {
    'keyword': keyword,
    'page': page,
    if (status case final status?) 'status': status.wireName,
  };
}

/// `liveSearch` 的一頁結果。
@immutable
final class LiveSearchPage {
  const LiveSearchPage({required this.items, required this.hasMore});

  factory LiveSearchPage.fromJson(
    Object? json, {
    required AllowedHosts allowedHosts,
  }) {
    const path = 'LiveSearchPage';
    final fields = JsonFields(json, sourceDtoShapes[path]!, path: path);
    final hasMore = fields.optionalBool('hasMore');
    return LiveSearchPage(
      items: List.unmodifiable([
        for (final (index, item) in fields.list('items').indexed)
          LiveRoom._fromJson(
            item,
            allowedHosts: allowedHosts,
            path: '$path.items[$index]',
          ),
      ]),
      hasMore:
          hasMore ?? (throw const FormatException('$path.hasMore: missing')),
    );
  }

  final List<LiveRoom> items;
  final bool hasMore;
}

/// 一個直播間（ADR 0028 §決定 3）。
@immutable
final class LiveRoom {
  const LiveRoom({
    required this.roomId,
    required this.title,
    this.hostName,
    this.artwork = const [],
    required this.status,
    this.online,
    this.area,
  });

  /// 解碼插件回傳的 `LiveRoom`（`liveStatus` 的回傳值）。
  factory LiveRoom.fromJson(
    Object? json, {
    required AllowedHosts allowedHosts,
  }) => LiveRoom._fromJson(json, allowedHosts: allowedHosts, path: 'LiveRoom');

  factory LiveRoom._fromJson(
    Object? json, {
    required AllowedHosts allowedHosts,
    required String path,
  }) {
    final fields = JsonFields(json, sourceDtoShapes['LiveRoom']!, path: path);
    final name = fields.string('status');
    final status = LiveRoomStatus.fromWireName(name);
    if (status == null) {
      throw FormatException('$path.status: unknown "$name"');
    }
    return LiveRoom(
      roomId: fields.nonEmptyString('roomId'),
      title: fields.nonEmptyString('title'),
      hostName: fields.optionalString('hostName'),
      artwork: List.unmodifiable([
        for (final (index, item)
            in (fields.optionalList('artwork') ?? []).indexed)
          Artwork._fromJson(
            item,
            allowedHosts: allowedHosts,
            path: '$path.artwork[$index]',
          ),
      ]),
      status: status,
      online: fields.optionalInteger('online'),
      // 去掉前後空白，空的當沒有（分區標籤只是裝飾，不為它拒收整個直播間）。
      area: switch (fields.optionalString('area')?.trim()) {
        final area? when area.isNotEmpty => area,
        _ => null,
      },
    );
  }

  /// 音源內的直播間 id。
  final String roomId;
  final String title;
  final String? hostName;
  final List<Artwork> artwork;
  final LiveRoomStatus status;

  /// 觀看人數；不知道就是 `null`。
  final int? online;

  /// 分區（遊戲、聊天之類）的短文字，已去掉前後空白；沒有就是 `null`（ADR 0035 §決定 10 補充）。
  final String? area;
}

/// `liveStatus` 的輸入（也是 checks.json 的 `live` 案例的輸入）。
@immutable
final class LiveRoomQuery {
  LiveRoomQuery({required this.roomId}) {
    if (roomId.trim().isEmpty) {
      throw ArgumentError.value(roomId, 'roomId', 'must not be empty');
    }
  }

  final String roomId;

  Map<String, Object?> toJson() => {'roomId': roomId};
}

/// `liveRoomFromUrl` 的輸入。
@immutable
final class LiveUrlQuery {
  LiveUrlQuery({required this.url}) {
    if (url.trim().isEmpty) {
      throw ArgumentError.value(url, 'url', 'must not be empty');
    }
  }

  final String url;

  Map<String, Object?> toJson() => {'url': url};
}

/// `liveRoomFromUrl` 認得網址時的回傳值。
@immutable
final class LiveRoomRef {
  const LiveRoomRef({required this.roomId});

  factory LiveRoomRef.fromJson(Object? json) {
    const path = 'LiveRoomRef';
    final fields = JsonFields(json, sourceDtoShapes[path]!, path: path);
    return LiveRoomRef(roomId: fields.nonEmptyString('roomId'));
  }

  final String roomId;
}

/// `resolveLive` 的輸入。
@immutable
final class LiveStreamRequest {
  LiveStreamRequest({required this.roomId, required this.formats}) {
    if (roomId.trim().isEmpty) {
      throw ArgumentError.value(roomId, 'roomId', 'must not be empty');
    }
    if (formats.isEmpty) {
      throw ArgumentError.value(formats, 'formats', 'must not be empty');
    }
  }

  final String roomId;

  /// 平台能播的格式，依使用者的格式偏好排過（同 [StreamRequest.formats]）。
  final List<StreamFormat> formats;

  Map<String, Object?> toJson() => {
    'roomId': roomId,
    'formats': [for (final format in formats) format.toJson()],
  };
}

/// `mix` 的輸入（ADR 0028 §決定 4）：以一首曲目開始一個 Mix，或以上一批回傳的
/// `mixId` 與 `cursor` 續取。
sealed class MixQuery {
  const MixQuery();

  Map<String, Object?> toJson();
}

/// 以 [sourceId]（與分 P 的 [cid]）為種子開始 Mix；也是 checks.json 的 `mix`
/// 案例的輸入。
@immutable
final class MixSeedQuery extends MixQuery {
  MixSeedQuery({required this.sourceId, this.cid}) {
    if (sourceId.trim().isEmpty) {
      throw ArgumentError.value(sourceId, 'sourceId', 'must not be empty');
    }
  }

  final String sourceId;
  final int? cid;

  @override
  Map<String, Object?> toJson() => {
    'seed': {'sourceId': sourceId, if (cid != null) 'cid': cid},
  };
}

/// 以 [mixId] 與插件上一次給的 [cursor] 續取下一批。
@immutable
final class MixContinueQuery extends MixQuery {
  MixContinueQuery({required this.mixId, required this.cursor}) {
    if (mixId.trim().isEmpty) {
      throw ArgumentError.value(mixId, 'mixId', 'must not be empty');
    }
    if (cursor.isEmpty) {
      throw ArgumentError.value(cursor, 'cursor', 'must not be empty');
    }
  }

  final String mixId;
  final String cursor;

  @override
  Map<String, Object?> toJson() => {'mixId': mixId, 'cursor': cursor};
}

/// `mix` 的一批結果。
@immutable
final class MixBatch {
  const MixBatch({
    required this.mixId,
    required this.title,
    required this.tracks,
    this.cursor,
  });

  factory MixBatch.fromJson(
    Object? json, {
    required String sourceTypeId,
    required AllowedHosts allowedHosts,
  }) {
    const path = 'MixBatch';
    final fields = JsonFields(json, sourceDtoShapes[path]!, path: path);
    final cursor = fields.optionalString('cursor');
    if (cursor != null && cursor.isEmpty) {
      throw const FormatException('$path.cursor: must not be empty');
    }
    return MixBatch(
      mixId: fields.nonEmptyString('mixId'),
      title: fields.nonEmptyString('title'),
      tracks: List.unmodifiable([
        for (final (index, item) in fields.list('tracks').indexed)
          TrackSummary._fromJson(
            item,
            sourceTypeId: sourceTypeId,
            allowedHosts: allowedHosts,
            path: '$path.tracks[$index]',
          ),
      ]),
      cursor: cursor,
    );
  }

  /// Mix 身分的一半（另一半是插件 id）。
  final String mixId;
  final String title;
  final List<TrackSummary> tracks;

  /// 插件的不透明字串；`null` 是這個 Mix 沒有更多。
  final String? cursor;
}

/// `multiPart` 的輸入（ADR 0028 §決定 5）。
@immutable
final class MultiPartQuery {
  MultiPartQuery({required this.sourceId}) {
    if (sourceId.trim().isEmpty) {
      throw ArgumentError.value(sourceId, 'sourceId', 'must not be empty');
    }
  }

  final String sourceId;

  Map<String, Object?> toJson() => {'sourceId': sourceId};
}

/// `multiPart` 的回傳值：一支影片的分 P。
@immutable
final class MultiPartResult {
  const MultiPartResult({required this.parts});

  factory MultiPartResult.fromJson(Object? json) {
    const path = 'MultiPartResult';
    final fields = JsonFields(json, sourceDtoShapes[path]!, path: path);
    final parts = [
      for (final (index, item) in fields.list('parts').indexed)
        MultiPart._fromJson(item, path: '$path.parts[$index]'),
    ];
    if (parts.isEmpty) {
      throw const FormatException('$path.parts: must not be empty');
    }
    return MultiPartResult(parts: List.unmodifiable(parts));
  }

  final List<MultiPart> parts;
}

/// 一個分 P。
@immutable
final class MultiPart {
  const MultiPart({
    required this.cid,
    required this.title,
    this.duration,
    required this.index,
  });

  factory MultiPart._fromJson(Object? json, {required String path}) {
    final fields = JsonFields(
      json,
      sourceDtoShapes['MultiPartItem']!,
      path: path,
    );
    final durationMs = fields.optionalInteger('durationMs');
    return MultiPart(
      cid: fields.integer('cid'),
      title: fields.nonEmptyString('title'),
      duration: durationMs == null ? null : Duration(milliseconds: durationMs),
      index: fields.integer('index', min: 1),
    );
  }

  final int cid;
  final String title;
  final Duration? duration;

  /// 從 1 起。
  final int index;

  /// 這個分 P 的曲目（ADR 0005：每個分 P 是一首曲目）：音源內的 id、上傳者與封面
  /// 沿用 [video]（影片本身），其餘用分 P 的；影片標題記在 `parentTitle`。
  TrackInfo toTrackInfo(TrackInfo video) => TrackInfo(
    sourceTypeId: video.sourceTypeId,
    sourceId: video.sourceId,
    cid: cid,
    title: title,
    uploader: video.uploader,
    duration: duration,
    artwork: video.artwork,
    partIndex: index,
    parentTitle: video.title,
  );
}

/// `trackDetail` 的輸入（ADR 0028 §決定 6）；也是 checks.json 的 `trackDetail` 案例
/// 的輸入。
@immutable
final class TrackDetailQuery {
  TrackDetailQuery({required this.sourceId, this.cid}) {
    if (sourceId.trim().isEmpty) {
      throw ArgumentError.value(sourceId, 'sourceId', 'must not be empty');
    }
  }

  final String sourceId;
  final int? cid;

  Map<String, Object?> toJson() => {
    'sourceId': sourceId,
    if (cid != null) 'cid': cid,
  };
}

/// 統計的種類（`fmp-plugin.d.ts` 的 `TrackStatKind`）。封閉的 union：宿主依它挑圖示與
/// 翻譯，不顯示插件給的文字。
enum TrackStatKind {
  view,
  like,
  favorite,
  comment,
  share,
  danmaku,
  coin;

  /// 插件介面上的名稱，與 [name] 分開寫死。
  String get wireName => switch (this) {
    view => 'view',
    like => 'like',
    favorite => 'favorite',
    comment => 'comment',
    share => 'share',
    danmaku => 'danmaku',
    coin => 'coin',
  };

  static TrackStatKind? fromWireName(String name) {
    for (final kind in values) {
      if (kind.wireName == name) return kind;
    }
    return null;
  }
}

/// 一項統計。
@immutable
final class TrackStat {
  const TrackStat({required this.kind, required this.count});

  factory TrackStat._fromJson(Object? json, {required String path}) {
    final fields = JsonFields(json, sourceDtoShapes['TrackStat']!, path: path);
    final name = fields.string('kind');
    final kind = TrackStatKind.fromWireName(name);
    if (kind == null) throw FormatException('$path.kind: unknown "$name"');
    return TrackStat(kind: kind, count: fields.integer('count'));
  }

  final TrackStatKind kind;

  /// 非負整數。
  final int count;
}

/// `trackDetail` 的回傳值：曲目的詳細資料，欄位都可以沒有。
@immutable
final class TrackDetail {
  const TrackDetail({
    this.description,
    this.publishedAt,
    this.uploaderAvatar = const [],
    this.album,
    this.stats = const [],
    this.webUrl,
  });

  factory TrackDetail.fromJson(
    Object? json, {
    required AllowedHosts allowedHosts,
  }) {
    const path = 'TrackDetail';
    final fields = JsonFields(json, sourceDtoShapes[path]!, path: path);
    final publishedAt = fields.optionalInteger('publishedAt');
    // DateTime 的上限是 8.64e15 毫秒：超過的不是時間。
    if (publishedAt != null && publishedAt > 8640000000000000) {
      throw const FormatException('$path.publishedAt: out of range');
    }
    return TrackDetail(
      description: fields.optionalString('description'),
      publishedAt: publishedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(publishedAt, isUtc: true),
      uploaderAvatar: List.unmodifiable([
        for (final (index, item)
            in (fields.optionalList('uploaderAvatar') ?? []).indexed)
          Artwork._fromJson(
            item,
            allowedHosts: allowedHosts,
            path: '$path.uploaderAvatar[$index]',
          ),
      ]),
      album: fields.optionalString('album'),
      stats: List.unmodifiable([
        for (final (index, item)
            in (fields.optionalList('stats') ?? []).indexed)
          TrackStat._fromJson(item, path: '$path.stats[$index]'),
      ]),
      webUrl: _webUrl(fields, allowedHosts, path),
    );
  }

  /// `webUrl`：`https` 且網域在 allowedHosts，不符就拒收（同 [Artwork.url]）。
  static Uri? _webUrl(
    JsonFields fields,
    AllowedHosts allowedHosts,
    String path,
  ) {
    final text = fields.optionalString('webUrl');
    if (text == null) return null;
    final url = Uri.tryParse(text);
    if (url == null || !allowedHosts.allows(url)) {
      throw FormatException(
        '$path.webUrl: must be an https URL on an allowed host',
      );
    }
    return url;
  }

  final String? description;

  /// UTC。
  final DateTime? publishedAt;
  final List<Artwork> uploaderAvatar;
  final String? album;
  final List<TrackStat> stats;

  /// 曲目在原網站的網頁（ADR 0035 §決定 10）；有才可以點開。
  final Uri? webUrl;

  /// 沒有任何欄位有內容。
  bool get isEmpty =>
      (description ?? '').trim().isEmpty &&
      publishedAt == null &&
      uploaderAvatar.isEmpty &&
      (album ?? '').trim().isEmpty &&
      stats.isEmpty &&
      webUrl == null;
}

/// `playlistFromUrl` 的輸入（ADR 0032 §決定 2）。
@immutable
final class PlaylistUrlQuery {
  PlaylistUrlQuery({required this.url}) {
    if (url.trim().isEmpty) {
      throw ArgumentError.value(url, 'url', 'must not be empty');
    }
  }

  final String url;

  Map<String, Object?> toJson() => {'url': url};
}

/// `playlistFromUrl` 認得網址時的回傳值：一張歌單（[PlaylistIdRef]）或一個 Mix 的種子
/// （[PlaylistMixSeedRef]）。
sealed class PlaylistRef {
  const PlaylistRef();

  /// 解碼插件回傳的值。[allowMixSeed] 是插件宣告了 `mix`：沒宣告卻回 `mixSeed`
  /// 是 [FormatException]（宿主之後沒有東西能開那個 Mix）。
  factory PlaylistRef.fromJson(Object? json, {required bool allowMixSeed}) {
    if (json case {'mixSeed': _}) {
      const path = 'PlaylistMixSeedRef';
      final fields = JsonFields(json, sourceDtoShapes[path]!, path: path);
      if (!allowMixSeed) {
        throw const FormatException(
          '$path: the plugin does not declare the mix capability',
        );
      }
      final seed = JsonFields(
        fields.raw('mixSeed'),
        sourceDtoShapes['MixSeed']!,
        path: '$path.mixSeed',
      );
      return PlaylistMixSeedRef(
        MixSeedQuery(
          sourceId: seed.nonEmptyString('sourceId'),
          cid: seed.optionalInteger('cid'),
        ),
      );
    }
    const path = 'PlaylistIdRef';
    final fields = JsonFields(json, sourceDtoShapes[path]!, path: path);
    return PlaylistIdRef(fields.nonEmptyString('playlistId'));
  }
}

/// 這個網址是插件的歌單，id 是 [playlistId]（音源內的 id，不透明）。
@immutable
final class PlaylistIdRef extends PlaylistRef {
  const PlaylistIdRef(this.playlistId);

  final String playlistId;
}

/// 這個網址是一個 Mix：[seed] 直接交給 `mix`。
@immutable
final class PlaylistMixSeedRef extends PlaylistRef {
  const PlaylistMixSeedRef(this.seed);

  final MixSeedQuery seed;
}

/// `importPlaylist` 的輸入：[cursor] 是上一頁回傳的，第一頁不給。
@immutable
final class PlaylistPageQuery {
  PlaylistPageQuery({required this.playlistId, this.cursor}) {
    if (playlistId.trim().isEmpty) {
      throw ArgumentError.value(playlistId, 'playlistId', 'must not be empty');
    }
    if (cursor != null && cursor!.isEmpty) {
      throw ArgumentError.value(cursor, 'cursor', 'must not be empty');
    }
  }

  final String playlistId;
  final String? cursor;

  Map<String, Object?> toJson() => {
    'playlistId': playlistId,
    if (cursor != null) 'cursor': cursor,
  };
}

/// `importPlaylist` 的一頁結果（ADR 0032 §決定 2）。
@immutable
final class PlaylistPage {
  const PlaylistPage({
    required this.playlist,
    required this.items,
    this.cursor,
    this.total,
    this.truncated = false,
  });

  factory PlaylistPage.fromJson(
    Object? json, {
    required String sourceTypeId,
    required AllowedHosts allowedHosts,
  }) {
    const path = 'PlaylistPage';
    final fields = JsonFields(json, sourceDtoShapes[path]!, path: path);
    final cursor = fields.optionalString('cursor');
    if (cursor != null && cursor.isEmpty) {
      throw const FormatException('$path.cursor: must not be empty');
    }
    final truncated = fields.optionalBool('truncated') ?? false;
    if (truncated && cursor != null) {
      throw const FormatException(
        '$path.truncated: only allowed on the last page (no cursor)',
      );
    }
    return PlaylistPage(
      playlist: RemotePlaylist._fromJson(
        fields.raw('playlist'),
        allowedHosts: allowedHosts,
        path: '$path.playlist',
      ),
      items: List.unmodifiable([
        for (final (index, item) in fields.list('items').indexed)
          RemotePlaylistItem._fromJson(
            item,
            sourceTypeId: sourceTypeId,
            allowedHosts: allowedHosts,
            path: '$path.items[$index]',
          ),
      ]),
      cursor: cursor,
      total: fields.optionalInteger('total'),
      truncated: truncated,
    );
  }

  /// 歌單本身的資料；每一頁都要給（宿主只在完整套用時才用）。
  final RemotePlaylist playlist;

  /// 這一頁的項目，可以是空的（空歌單、或最後一頁剛好沒東西）。
  final List<RemotePlaylistItem> items;

  /// 插件的不透明字串；`null` 是最後一頁。
  final String? cursor;

  /// 整張歌單的筆數（非負）；插件只在確定等於會回傳的筆數時才給。
  final int? total;

  /// 只會出現在最後一頁：插件已讀完它讀得到的，但遠端歌單可能還有更多（例如 Spotify embed
  /// 頁只給前 100 首）。刷新視為不完整；外部匯入照常匹配並提示。
  final bool truncated;
}

/// 遠端歌單本身的資料。
@immutable
final class RemotePlaylist {
  const RemotePlaylist({
    required this.title,
    this.description,
    this.artwork = const [],
    this.ownerName,
    this.writable,
  });

  factory RemotePlaylist._fromJson(
    Object? json, {
    required AllowedHosts allowedHosts,
    required String path,
  }) {
    final fields = JsonFields(
      json,
      sourceDtoShapes['RemotePlaylist']!,
      path: path,
    );
    return RemotePlaylist(
      title: fields.nonEmptyString('title'),
      description: fields.optionalString('description'),
      artwork: List.unmodifiable([
        for (final (index, item)
            in (fields.optionalList('artwork') ?? []).indexed)
          Artwork._fromJson(
            item,
            allowedHosts: allowedHosts,
            path: '$path.artwork[$index]',
          ),
      ]),
      ownerName: fields.optionalString('ownerName'),
      writable: fields.optionalBool('writable'),
    );
  }

  final String title;
  final String? description;
  final List<Artwork> artwork;
  final String? ownerName;

  /// 這張是登入的帳號自己的、可以寫；`null` 是這次不知道（沒帶憑證），宿主保留上次的值。
  final bool? writable;

  /// 資料層與音樂庫用的歌單資料：欄位逐一照搬。
  RemotePlaylistInfo toInfo() => RemotePlaylistInfo(
    name: title,
    description: description,
    artwork: List.unmodifiable([
      for (final image in artwork)
        TrackArtwork(url: image.url, width: image.width),
    ]),
    ownerName: ownerName,
    writable: writable,
  );
}

/// 遠端歌單的一個項目。
@immutable
final class RemotePlaylistItem {
  const RemotePlaylistItem({
    required this.track,
    this.remoteItemId,
    this.unavailable = false,
  });

  factory RemotePlaylistItem._fromJson(
    Object? json, {
    required String sourceTypeId,
    required AllowedHosts allowedHosts,
    required String path,
  }) {
    final fields = JsonFields(
      json,
      sourceDtoShapes['RemotePlaylistItem']!,
      path: path,
    );
    final remoteItemId = fields.optionalString('remoteItemId');
    if (remoteItemId != null && remoteItemId.isEmpty) {
      throw FormatException('$path.remoteItemId: must not be empty');
    }
    return RemotePlaylistItem(
      track: TrackSummary._fromJson(
        fields.raw('track'),
        sourceTypeId: sourceTypeId,
        allowedHosts: allowedHosts,
        path: '$path.track',
      ),
      remoteItemId: remoteItemId,
      unavailable: fields.optionalBool('unavailable') ?? false,
    );
  }

  final TrackSummary track;

  /// 遠端項目的 id（YouTube 的 `setVideoId`），移除要用；同一首可以在歌單裡出現多次。
  final String? remoteItemId;

  /// 遠端標的失效（被刪、被隱藏）。
  final bool unavailable;

  /// 資料層與音樂庫用的項目：欄位逐一照搬。
  RemoteEntry toEntry() => RemoteEntry(
    track: track.toTrackInfo(),
    remoteItemId: remoteItemId,
    unavailable: unavailable,
  );
}

/// `chartList` 回傳的榜單清單（ADR 0032 §決定 5）。
@immutable
final class ChartList {
  const ChartList({required this.charts});

  factory ChartList.fromJson(Object? json) {
    const path = 'ChartList';
    final fields = JsonFields(json, sourceDtoShapes[path]!, path: path);
    final charts = List<ChartRef>.unmodifiable([
      for (final (index, item) in fields.list('charts').indexed)
        ChartRef._fromJson(item, path: '$path.charts[$index]'),
    ]);
    final seen = <String>{};
    for (final (index, chart) in charts.indexed) {
      if (!seen.add(chart.chartId)) {
        throw FormatException(
          '$path.charts[$index].chartId: "${chart.chartId}" is listed twice',
        );
      }
    }
    return ChartList(charts: charts);
  }

  /// 可以是空的（插件暫時沒有榜單）；`chartId` 不重複。
  final List<ChartRef> charts;
}

/// 一個榜單的身分與顯示名稱。
@immutable
final class ChartRef {
  const ChartRef({required this.chartId, required this.title});

  factory ChartRef._fromJson(Object? json, {required String path}) {
    final fields = JsonFields(json, sourceDtoShapes['ChartRef']!, path: path);
    return ChartRef(
      chartId: fields.nonEmptyString('chartId'),
      title: fields.nonEmptyString('title'),
    );
  }

  /// 音源內的榜單 id（不透明），之後原樣交給 `chart`。
  final String chartId;
  final String title;
}

/// `chart` 的輸入。
@immutable
final class ChartQuery {
  ChartQuery({required this.chartId}) {
    if (chartId.trim().isEmpty) {
      throw ArgumentError.value(chartId, 'chartId', 'must not be empty');
    }
  }

  final String chartId;

  Map<String, Object?> toJson() => {'chartId': chartId};
}

/// `chart` 的回傳值：榜單的曲目，依插件給的順序。
@immutable
final class ChartPage {
  const ChartPage({required this.tracks});

  factory ChartPage.fromJson(
    Object? json, {
    required String sourceTypeId,
    required AllowedHosts allowedHosts,
  }) {
    const path = 'ChartPage';
    final fields = JsonFields(json, sourceDtoShapes[path]!, path: path);
    return ChartPage(
      tracks: List.unmodifiable([
        for (final (index, item) in fields.list('tracks').indexed)
          TrackSummary._fromJson(
            item,
            sourceTypeId: sourceTypeId,
            allowedHosts: allowedHosts,
            path: '$path.tracks[$index]',
          ),
      ]),
    );
  }

  /// 可以是空的（空榜單顯示「沒有內容」）。
  final List<TrackSummary> tracks;
}

/// `libraryPlaylists` 的輸入：[cursor] 是上一頁回傳的，第一頁不給。
@immutable
final class LibraryPlaylistsQuery {
  LibraryPlaylistsQuery({this.cursor}) {
    if (cursor != null && cursor!.isEmpty) {
      throw ArgumentError.value(cursor, 'cursor', 'must not be empty');
    }
  }

  final String? cursor;

  Map<String, Object?> toJson() => {if (cursor != null) 'cursor': cursor};
}

/// `libraryPlaylists` 的一頁結果（ADR 0032 §決定 3）：登入帳號自己的歌單。
@immutable
final class LibraryPlaylistPage {
  const LibraryPlaylistPage({required this.playlists, this.cursor});

  factory LibraryPlaylistPage.fromJson(
    Object? json, {
    required AllowedHosts allowedHosts,
  }) {
    const path = 'LibraryPlaylistPage';
    final fields = JsonFields(json, sourceDtoShapes[path]!, path: path);
    final cursor = fields.optionalString('cursor');
    if (cursor != null && cursor.isEmpty) {
      throw const FormatException('$path.cursor: must not be empty');
    }
    final playlists = List<LibraryPlaylist>.unmodifiable([
      for (final (index, item) in fields.list('playlists').indexed)
        LibraryPlaylist._fromJson(
          item,
          allowedHosts: allowedHosts,
          path: '$path.playlists[$index]',
        ),
    ]);
    final seen = <String>{};
    for (final (index, playlist) in playlists.indexed) {
      if (!seen.add(playlist.playlistId)) {
        throw FormatException(
          '$path.playlists[$index].playlistId: '
          '"${playlist.playlistId}" is listed twice',
        );
      }
    }
    return LibraryPlaylistPage(playlists: playlists, cursor: cursor);
  }

  /// 這一頁的歌單，可以是空的；同一頁內 `playlistId` 不重複。
  final List<LibraryPlaylist> playlists;

  /// 插件的不透明字串；`null` 是最後一頁。
  final String? cursor;
}

/// `libraryLiveRooms` 的回傳值（ADR 0032 §決定 3）：登入帳號關注的直播間。
@immutable
final class LibraryLiveRooms {
  const LibraryLiveRooms({required this.rooms});

  factory LibraryLiveRooms.fromJson(
    Object? json, {
    required AllowedHosts allowedHosts,
  }) {
    const path = 'LibraryLiveRooms';
    final fields = JsonFields(json, sourceDtoShapes[path]!, path: path);
    final rooms = List<LiveRoom>.unmodifiable([
      for (final (index, item) in fields.list('rooms').indexed)
        LiveRoom._fromJson(
          item,
          allowedHosts: allowedHosts,
          path: '$path.rooms[$index]',
        ),
    ]);
    // 同 LibraryPlaylistPage：重複的鍵拒收，不默默丟掉。
    final seen = <String>{};
    for (final (index, room) in rooms.indexed) {
      if (!seen.add(room.roomId)) {
        throw FormatException(
          '$path.rooms[$index].roomId: "${room.roomId}" is listed twice',
        );
      }
    }
    return LibraryLiveRooms(rooms: rooms);
  }

  /// 可以是空的；`roomId` 不重複。
  final List<LiveRoom> rooms;
}

/// 登入帳號在平台上的一張歌單。
@immutable
final class LibraryPlaylist {
  const LibraryPlaylist({
    required this.playlistId,
    required this.title,
    this.artwork = const [],
    this.trackCount,
    required this.writable,
  });

  factory LibraryPlaylist._fromJson(
    Object? json, {
    required AllowedHosts allowedHosts,
    required String path,
  }) {
    final fields = JsonFields(
      json,
      sourceDtoShapes['LibraryPlaylist']!,
      path: path,
    );
    return LibraryPlaylist(
      playlistId: fields.nonEmptyString('playlistId'),
      title: fields.nonEmptyString('title'),
      artwork: List.unmodifiable([
        for (final (index, item)
            in (fields.optionalList('artwork') ?? []).indexed)
          Artwork._fromJson(
            item,
            allowedHosts: allowedHosts,
            path: '$path.artwork[$index]',
          ),
      ]),
      trackCount: fields.optionalInteger('trackCount'),
      // 欄位表已擋掉沒給的情況。
      writable: fields.optionalBool('writable')!,
    );
  }

  /// 音源內的歌單 id（不透明），之後原樣交給 `importPlaylist`。
  final String playlistId;
  final String title;

  /// 多尺寸封面，規則同 [TrackSummary.artwork]。
  final List<Artwork> artwork;

  /// 非負；不知道就是 `null`。
  final int? trackCount;

  /// 這張是帳號自己的、可以寫（`libraryWrite`）。
  final bool writable;
}

/// `createPlaylist` 的輸入：[title] 去掉頭尾空白後不得為空（呼叫端先整理）。
@immutable
final class CreatePlaylistQuery {
  CreatePlaylistQuery({required String title}) : title = title.trim() {
    if (this.title.isEmpty) {
      throw ArgumentError.value(title, 'title', 'must not be empty');
    }
  }

  final String title;

  Map<String, Object?> toJson() => {'title': title};
}

/// `createPlaylist` 的回傳值：新歌單在音源內的 id（不透明，之後原樣交給 `addToPlaylist`、
/// `importPlaylist`）。
@immutable
final class CreatePlaylistResult {
  const CreatePlaylistResult({required this.playlistId});

  factory CreatePlaylistResult.fromJson(Object? json) {
    const path = 'CreatePlaylistResult';
    final fields = JsonFields(json, sourceDtoShapes[path]!, path: path);
    return CreatePlaylistResult(
      playlistId: fields.nonEmptyString('playlistId'),
    );
  }

  final String playlistId;
}

/// `addToPlaylist` 要加的一首。
@immutable
final class AddTrackRef {
  AddTrackRef({required this.sourceId, this.cid}) {
    if (sourceId.isEmpty) {
      throw ArgumentError.value(sourceId, 'sourceId', 'must not be empty');
    }
    if (cid != null && cid! < 0) {
      throw ArgumentError.value(cid, 'cid', 'must not be negative');
    }
  }

  final String sourceId;
  final int? cid;

  Map<String, Object?> toJson() => {
    'sourceId': sourceId,
    if (cid != null) 'cid': cid,
  };
}

/// `addToPlaylist` 的輸入：[tracks] 至少一首。
@immutable
final class AddToPlaylistQuery {
  AddToPlaylistQuery({required this.playlistId, required this.tracks}) {
    if (playlistId.isEmpty) {
      throw ArgumentError.value(playlistId, 'playlistId', 'must not be empty');
    }
    if (tracks.isEmpty) {
      throw ArgumentError.value(tracks, 'tracks', 'must not be empty');
    }
  }

  final String playlistId;
  final List<AddTrackRef> tracks;

  Map<String, Object?> toJson() => {
    'playlistId': playlistId,
    'tracks': [for (final track in tracks) track.toJson()],
  };
}

/// `removeFromPlaylist` 要移除的一項：[remoteItemId] 是遠端項目的 id（匯入時 `importPlaylist`
/// 給的），沒有的音源以 [sourceId]（與 [cid]）找。
@immutable
final class RemoveItemRef {
  RemoveItemRef({required this.sourceId, this.cid, this.remoteItemId}) {
    if (sourceId.isEmpty) {
      throw ArgumentError.value(sourceId, 'sourceId', 'must not be empty');
    }
    if (cid != null && cid! < 0) {
      throw ArgumentError.value(cid, 'cid', 'must not be negative');
    }
    if (remoteItemId != null && remoteItemId!.isEmpty) {
      throw ArgumentError.value(
        remoteItemId,
        'remoteItemId',
        'must not be empty',
      );
    }
  }

  final String sourceId;
  final int? cid;
  final String? remoteItemId;

  Map<String, Object?> toJson() => {
    'sourceId': sourceId,
    if (cid != null) 'cid': cid,
    if (remoteItemId != null) 'remoteItemId': remoteItemId,
  };
}

/// `removeFromPlaylist` 的輸入：[items] 至少一項。
@immutable
final class RemoveFromPlaylistQuery {
  RemoveFromPlaylistQuery({required this.playlistId, required this.items}) {
    if (playlistId.isEmpty) {
      throw ArgumentError.value(playlistId, 'playlistId', 'must not be empty');
    }
    if (items.isEmpty) {
      throw ArgumentError.value(items, 'items', 'must not be empty');
    }
  }

  final String playlistId;
  final List<RemoveItemRef> items;

  Map<String, Object?> toJson() => {
    'playlistId': playlistId,
    'items': [for (final item in items) item.toJson()],
  };
}

/// 寫入結果裡一項的狀態（ADR 0032 §決定 4）；[wireName] 是插件介面上的字串。
enum LibraryWriteStatus {
  /// `addToPlaylist`：加進去了。
  added('added'),

  /// `addToPlaylist`：歌單裡本來就有（去重在插件內做）。
  alreadyPresent('alreadyPresent'),

  /// `removeFromPlaylist`：移除了。
  removed('removed'),

  /// `removeFromPlaylist`：歌單裡本來就沒有。
  notPresent('notPresent'),

  /// 這一項失敗，原因在 [LibraryWriteResult.error]。
  failed('failed');

  const LibraryWriteStatus(this.wireName);

  final String wireName;

  static const forAdd = {added, alreadyPresent, failed};
  static const forRemove = {removed, notPresent, failed};
}

/// 寫入結果裡的一項，對應輸入的同一個位置。
@immutable
final class LibraryWriteResult {
  const LibraryWriteResult({required this.status, this.error});

  /// [shape] 是 `AddToPlaylistResult` 或 `RemoveFromPlaylistResult`（欄位相同，d.ts 的狀態
  /// union 不同）。
  factory LibraryWriteResult._fromJson(
    Object? json, {
    required Set<LibraryWriteStatus> allowed,
    required String shape,
    required String pluginId,
    required String path,
  }) {
    final fields = JsonFields(json, sourceDtoShapes[shape]!, path: path);
    final name = fields.string('status');
    final status = allowed.where((value) => value.wireName == name).firstOrNull;
    if (status == null) {
      throw FormatException('$path.status: unknown "$name"');
    }
    final error = fields.optionalObject('error');
    if (error != null && status != LibraryWriteStatus.failed) {
      throw FormatException('$path.error: only a failed result has an error');
    }
    return LibraryWriteResult(
      status: status,
      error: error == null
          ? null
          : _structuredError(error, pluginId, '$path.error'),
    );
  }

  final LibraryWriteStatus status;

  /// 只有 [LibraryWriteStatus.failed] 可能有；插件沒說原因就是 `null`。
  final AppError? error;
}

/// 結構化錯誤轉成 [AppError]，和插件拋出的結構化錯誤走同一個函式（`structuredScriptError`）。
AppError _structuredError(
  Map<String, Object?> json,
  String pluginId,
  String path,
) {
  final fields = JsonFields(json, sourceDtoShapes['FmpError']!, path: path);
  final retryAfter = fields.raw('retryAfterSeconds');
  if (retryAfter != null && retryAfter is! num) {
    throw FormatException('$path.retryAfterSeconds: expected a number');
  }
  return structuredScriptError(
    pluginId: pluginId,
    fmpError: fields.string('fmpError'),
    retryAfterSeconds: retryAfter as num?,
    reason: fields.optionalString('reason'),
    message: fields.optionalString('message'),
  );
}

List<LibraryWriteResult> _writeResults(
  Object? json, {
  required String path,
  required String itemShape,
  required Set<LibraryWriteStatus> allowed,
  required String pluginId,
  required int expected,
}) {
  final fields = JsonFields(json, sourceDtoShapes[path]!, path: path);
  final items = fields.list('results');
  if (items.length != expected) {
    throw FormatException(
      '$path.results: expected $expected results, got ${items.length}',
    );
  }
  return List.unmodifiable([
    for (final (index, item) in items.indexed)
      LibraryWriteResult._fromJson(
        item,
        allowed: allowed,
        shape: itemShape,
        pluginId: pluginId,
        path: '$path.results[$index]',
      ),
  ]);
}

/// `addToPlaylist` 的回傳值：[results] 與輸入的 `tracks` 同長同順序。
@immutable
final class AddToPlaylistResponse {
  const AddToPlaylistResponse({required this.results});

  /// [expected] 是輸入的筆數；長度不符、`status` 不在 `added`／`alreadyPresent`／`failed`、
  /// `error` 出現在非 `failed` 的項目都是 [FormatException]。
  factory AddToPlaylistResponse.fromJson(
    Object? json, {
    required String pluginId,
    required int expected,
  }) => AddToPlaylistResponse(
    results: _writeResults(
      json,
      path: 'AddToPlaylistResponse',
      itemShape: 'AddToPlaylistResult',
      allowed: LibraryWriteStatus.forAdd,
      pluginId: pluginId,
      expected: expected,
    ),
  );

  final List<LibraryWriteResult> results;
}

/// `removeFromPlaylist` 的回傳值：[results] 與輸入的 `items` 同長同順序。
@immutable
final class RemoveFromPlaylistResponse {
  const RemoveFromPlaylistResponse({required this.results});

  /// 規則同 [AddToPlaylistResponse.fromJson]，狀態是 `removed`／`notPresent`／`failed`。
  factory RemoveFromPlaylistResponse.fromJson(
    Object? json, {
    required String pluginId,
    required int expected,
  }) => RemoveFromPlaylistResponse(
    results: _writeResults(
      json,
      path: 'RemoveFromPlaylistResponse',
      itemShape: 'RemoveFromPlaylistResult',
      allowed: LibraryWriteStatus.forRemove,
      pluginId: pluginId,
      expected: expected,
    ),
  );

  final List<LibraryWriteResult> results;
}
