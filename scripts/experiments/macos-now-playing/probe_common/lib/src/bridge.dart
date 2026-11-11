/// 一首測試曲目要送給 Now Playing 的資訊。
class TrackInfo {
  const TrackInfo({
    required this.index,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.audioPath,
    required this.artPath,
    this.artUrl,
  });

  final int index;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final String audioPath;

  /// PNG 封面的本機路徑。
  final String artPath;

  /// 有設 `--dart-define=ART_BASE=<網址>` 時，同一張封面的 HTTP 網址（run.py 起本機 server）。
  final String? artUrl;
}

/// 候選收到系統指令時呼叫的播放器操作。
abstract interface class PlayerController {
  Future<void> play();
  Future<void> pause();
  Future<void> togglePlayPause();
  Future<void> next();
  Future<void> previous();
  Future<void> seek(Duration position);

  /// 記一筆收到的系統指令（畫面、stdout、結果檔各一份）。
  void logCommand(String command, [Object? detail]);
}

/// 一個 Now Playing 接法。
abstract interface class NowPlayingBridge {
  String get name;

  Future<void> init(PlayerController controller);

  /// 換歌時呼叫（含第一次載入）。
  Future<void> setTrack(TrackInfo track);

  /// 播放、暫停、seek、換歌後呼叫；系統依 position 與 rate 自己推算進度。
  Future<void> setPlayback({required bool playing, required Duration position});
}
