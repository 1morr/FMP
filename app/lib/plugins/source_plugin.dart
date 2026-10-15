import 'package:fmp/plugins/accounts/login_credentials.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/source_dto.dart';

/// 一個音源（ADR 0014 §決定 1）。App 其他部分只認這個介面與 [manifest] 的
/// 能力宣告，分不出來源是誰、是不是腳本。
///
/// 方法只在引入它們的里程碑加，不先寫空殼。呼叫沒宣告的能力（或 `login` 沒宣告
/// 的方式、刷新）拋 `Unsupported`。
///
/// 丟出的錯誤都是 `AppError`（ADR 0013 §決定 2）。
abstract interface class SourcePlugin {
  PluginManifest get manifest;

  /// 插件還能不能用。
  PluginHealth get health;

  /// 插件變成 [PluginHealth.unresponsive] 時完成；一直正常就不會完成。
  Future<void> get whenUnresponsive;

  /// [PluginCapability.search]。
  Future<SearchPage> search(SearchQuery query);

  /// [PluginCapability.resolveStream]：依優先序排好的候選（至少一個），以及它們
  /// 是不是只有試聽片段。
  Future<StreamResult> resolveStream(StreamRequest request);

  /// [PluginCapability.live]：搜尋直播間（ADR 0028 §決定 3）。
  Future<LiveSearchPage> liveSearch(LiveSearchQuery query);

  /// 這個網址是不是這個插件的直播間網址；不是回 `null`。插件可以為短網址發請求。
  Future<LiveRoomRef?> liveRoomFromUrl(LiveUrlQuery query);

  /// 直播間現在的狀態。**查詢失敗一律拋錯，不能回 [LiveRoomStatus.offline]**
  /// （D10）：呼叫端把拋錯顯示成「查詢失敗」，未開播是另一回事。
  Future<LiveRoom> liveStatus(LiveRoomQuery query);

  /// 直播流；`expiresAt` 可以是空的。
  Future<StreamResult> resolveLive(LiveStreamRequest request);

  /// [PluginCapability.mix]：開始一個 Mix（[MixSeedQuery]）或續取下一批
  /// （[MixContinueQuery]，ADR 0028 §決定 4）。
  Future<MixBatch> mix(MixQuery query);

  /// [PluginCapability.importPlaylist]：這個網址是不是這個插件的歌單（或 Mix）；不是
  /// 回 `null`。插件可以為短網址發請求；`mixSeed` 只有同時宣告 `mix` 的插件能回
  /// （ADR 0032 §決定 2）。
  Future<PlaylistRef?> playlistFromUrl(PlaylistUrlQuery query);

  /// 歌單的一頁（第一頁不給 `cursor`）。遠端歌單不存在或沒有權限讀是 `NotFound`，
  /// 要登入才讀得到而沒有登入是 `AuthRequired`。
  Future<PlaylistPage> importPlaylist(PlaylistPageQuery query);

  /// [PluginCapability.multiPart]：一支影片的分 P（ADR 0028 §決定 5）。
  Future<MultiPartResult> multiPart(MultiPartQuery query);

  /// [PluginCapability.trackDetail]：曲目的詳細資料（ADR 0028 §決定 6）。
  Future<TrackDetail> trackDetail(TrackDetailQuery query);

  /// [PluginCapability.login] 的 QR 登入（methods 含 `qr`）：產生一個 QR 碼。
  Future<LoginQrCode> loginQrStart();

  /// QR 登入的進度；`done` 時帶憑證。
  Future<LoginQrPoll> loginQrPoll(String token);

  /// 驗證 [credentials] 屬於哪個帳號（ADR 0012 §決定 4）：三種方式拿到憑證之後、
  /// 寫入之前呼叫。呼叫前 [credentials] 的值已登記到遮蔽函式，失敗也不取消。
  Future<LoginAccount> loginVerify(LoginCredentials credentials);

  /// 刷新 [credentials]（宣告 `refresh` 的插件）：新的憑證，或不需要／沒有新的時
  /// `null`；刷新失敗拋 `CredentialInvalid`。遮蔽同 [loginVerify]。
  Future<LoginCredentials?> loginRefresh(LoginCredentials credentials);

  /// 釋放資源（JS runtime、連線）。之後的呼叫失敗。
  void close();
}

/// 插件的狀態（prd 擁有者決定 7）。
enum PluginHealth {
  ready,

  /// 呼叫逾時而背景 isolate 也不回應探測，或背景 isolate 意外結束。之後的
  /// 呼叫一律失敗，直到 App 重啟。
  unresponsive,
}
