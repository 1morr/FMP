import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/source_http_policy.dart';
import 'package:fmp/services/account/source_auth_context.dart';

/// 沒有登入帳號時的 [SourceAuthContext]。
///
/// `authForPlay` 一律回 null（沒有憑證），`playbackNetworkRequest` 原樣把 URL
/// 交回去、只補上該音源的公開媒體 header。這是「未登入的正常狀態」，不是
/// 退化路徑 —— 大多數播放測試要的就是這個。
///
/// 其餘成員故意不實作，交給 `noSuchMethod`：真的被呼叫到會拋
/// `NoSuchMethodError`，那比默默回一個假值容易查。需要記錄呼叫、注入
/// per-source header 或覆寫歌單授權的測試，請在該檔案裡自己寫一個 —— 那些
/// 差異是測試本身要表達的東西，塞進共用替身只會變成一堆沒人記得的開關。
class FakeSourceAuthContext implements SourceAuthContext {
  @override
  Future<Map<String, String>?> authForPlay(String sourceType) async => null;

  @override
  Future<PlaybackNetworkRequest> playbackNetworkRequest(
    Track track,
    String url,
  ) async {
    return PlaybackNetworkRequest(
      url: url,
      headers: SourceHttpPolicy.mediaHeaders(track.sourceType),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
