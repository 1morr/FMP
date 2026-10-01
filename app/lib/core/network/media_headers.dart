/// 媒體請求（抓音訊位元組）可以帶的 header，小寫。
///
/// ADR 0012：憑證只用在向音源解析串流與 API 請求，抓音訊位元組的請求一律不帶
/// 憑證，只帶媒體 headers。其他 header 一律丟掉，所以之後插件多給的
/// `Cookie`、`Authorization` 或任何自訂憑證 header 都到不了 CDN。
const mediaHeaderNames = {'referer', 'user-agent', 'origin', 'range'};

/// 媒體 header 政策：從插件給的串流 [headers] 只留 [mediaHeaderNames]（名稱
/// 不分大小寫，保留原本的寫法與值）。
///
/// 播放後端與媒體 client（`media_http_client.dart`）拿到的 headers 都要先經過它。
Map<String, String> mediaRequestHeaders(Map<String, String> headers) => {
  for (final MapEntry(:key, :value) in headers.entries)
    if (mediaHeaderNames.contains(key.toLowerCase())) key: value,
};
