/// 實驗用（可丟棄）：macOS Now Playing 實驗兩個候選共用的播放器、測試曲目與畫面。
///
/// 候選只要實作 [NowPlayingBridge]：把曲目資訊與播放狀態送給系統，
/// 把系統送來的指令轉給 [PlayerController]。
library;

export 'src/bridge.dart';
export 'src/probe_app.dart';
