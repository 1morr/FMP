import 'package:flutter/foundation.dart';

import 'package:fmp/core/network/allowed_hosts.dart';
import 'package:fmp/domain/stream_preferences.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/plugins/accounts/login_credentials.dart';
import 'package:fmp/core/json_shape.dart';

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
  });

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
