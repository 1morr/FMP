import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/source_dto.dart';

/// 一個音源（ADR 0014 §決定 1）。App 其他部分只認這個介面與 [manifest] 的
/// 能力宣告，分不出來源是誰、是不是腳本。
///
/// 方法只在引入它們的里程碑加，不先寫空殼；M1 只有 [search] 與
/// [resolveStream]。呼叫沒宣告的能力拋 `Unsupported`。
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
