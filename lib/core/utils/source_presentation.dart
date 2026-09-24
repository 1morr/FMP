import 'package:fmp/data/models/track.dart';

/// 內容是歌曲而不是影片的音源。
///
/// 詳情的呈現因此不同：方形封面、歌手與專輯、評論數，標題叫「歌曲資訊」；
/// 其餘音源是影片：16:9 封面、UP 主或頻道、播放與按讚數。不在這裡的音源
/// 一律照影片呈現。
const Set<String> songSources = {SourceIds.netease};

/// 詳情裡沒有收藏數的音源（YouTube 沒有這個數字）。
const Set<String> sourcesWithoutFavoriteCount = {SourceIds.youtube};

bool isSongSource(String? sourceType) => songSources.contains(sourceType);

bool showsFavoriteCount(String? sourceType) =>
    !sourcesWithoutFavoriteCount.contains(sourceType);
