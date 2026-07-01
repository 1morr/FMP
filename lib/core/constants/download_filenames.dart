/// 下載檔案命名常數——寫入端（DownloadService）與掃描/讀取端
/// （DownloadScanner、TrackExtensions、各 provider/UI）共用的隱性契約。
///
/// 任一處改名須全程同步，故集中為常數（C8 / 01-action-plan.md）。
/// 注意：多頁 `metadata_P{N}.json` 與音訊副檔名（.m4a/.mp3/…）的資料驅動化
/// 屬後續 D13，不在此處（避免把「寫死的單一副檔名」固化為常數）。
class DownloadFileNames {
  DownloadFileNames._();

  /// 封面圖檔名（每個下載影片資料夾內）。
  static const String cover = 'cover.jpg';

  /// 創作者頭像檔名。
  static const String avatar = 'avatar.jpg';

  /// 單頁後設資料檔名。
  static const String metadata = 'metadata.json';
}
