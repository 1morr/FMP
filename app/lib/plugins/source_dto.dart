import 'package:flutter/foundation.dart';

import 'package:fmp/core/network/allowed_hosts.dart';
import 'package:fmp/domain/stream_preferences.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/plugins/accounts/login_credentials.dart';
import 'package:fmp/plugins/json_shape.dart';

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
