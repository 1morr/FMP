import 'package:path/path.dart' as p;

/// 下載檔案命名常數——寫入端（DownloadService）與掃描/讀取端
/// （DownloadScanner、TrackExtensions、各 provider/UI）共用的隱性契約。
///
/// 任一處改名須全程同步，故集中為常數。
/// 注意：多頁 `metadata_P{N}.json` 與音訊副檔名（.m4a/.mp3/…）仍不是常數，
/// 但兩者的**配對規則**已集中在 `metadataCandidatesForAudio`（寫入端、掃描端、
/// 刪除端與詳情頁共用同一份，不再各自複製）；資料驅動化屬後續 D13，尚未做。
class DownloadFileNames {
  DownloadFileNames._();

  /// 封面圖檔名（每個下載影片資料夾內）。
  static const String cover = 'cover.jpg';

  /// 創作者頭像檔名。
  static const String avatar = 'avatar.jpg';

  /// 單頁後設資料檔名。
  static const String metadata = 'metadata.json';

  /// 音訊檔名 → 配對 metadata 檔名候選（優先序遞減）。
  /// 多頁 P{N} 檔名先找 `metadata_P{N}.json`，找不到退回共用的 `metadata.json`
  /// （scanner 對舊版佈局的既有退路）；單頁只有 `metadata.json`。
  ///
  /// 只認「檔名恰好是 `P{N}`」的佈局；舊版的 `P{N} - 標題.m4a` 一律配對共用
  /// `metadata.json`（舊版佈局本來就是共用的，且這種檔名拆不出可靠的分頁號）。
  static List<String> metadataCandidatesForAudio(String audioFileName) {
    final name = p.basenameWithoutExtension(audioFileName);
    final pageMatch = RegExp(r'^P(\d+)$').firstMatch(name);
    if (pageMatch == null) return [metadata];
    return ['metadata_P${pageMatch.group(1)}.json', metadata];
  }
}
