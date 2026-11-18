import 'package:fmp/domain/audio_stream.dart';

/// 兩個音訊後端共用的帳本：原生播放器的清單裡依序放了哪幾條串流（目前這條，
/// 加上最多一條預載的），原生的位置在哪。串流以物件身分（[identical]）認，
/// 同樣網址的兩次解析算兩條。
///
/// 只記帳、不碰原生播放器：後端照它回的改法改原生清單，原生的位置變了
/// （自己接到下一條，或跳過去）再告訴它（[moved]）。
class BackendPlaylist {
  final _items = <AudioStream>[];
  int _index = 0;

  /// 原生正在放的那條；還沒載入過、或清掉之後是 null。
  AudioStream? get current => _items.isEmpty ? null : _items[_index];

  /// 排在目前這條後面的那條；沒有是 null。
  AudioStream? get preloaded =>
      _index + 1 < _items.length ? _items[_index + 1] : null;

  /// 開了新的一條（原生清單整個換掉）：清單只剩它。
  void opened(AudioStream stream) {
    _items
      ..clear()
      ..add(stream);
    _index = 0;
  }

  /// 原生清單沒有可信的內容了（載入失敗、被取代、釋放）。
  void clear() {
    _items.clear();
    _index = 0;
  }

  /// 把預載換成 [stream]（null 是清掉）要怎麼改原生清單，並照改法記帳。
  /// 沒有目前這條時是 null，什麼都別改。
  PreloadEdit? preload(AudioStream? stream) {
    if (current == null) return null;
    if (stream != null && identical(preloaded, stream)) {
      return const PreloadEdit(remove: [], append: null);
    }
    final remove = [for (var i = _items.length - 1; i > _index; i--) i];
    _items.removeRange(_index + 1, _items.length);
    if (stream != null) _items.add(stream);
    return PreloadEdit(remove: remove, append: stream);
  }

  /// 要載入 [stream] 時怎麼做：預載的那條就跳過去，正在放的就不動，其他
  /// 重開。
  LoadPlan planLoad(AudioStream stream) {
    if (identical(current, stream)) return const AlreadyCurrent();
    if (identical(preloaded, stream)) return SwitchTo(_index + 1);
    return const Reopen();
  }

  /// 原生的位置變成 [index]：換了一條就回傳它（它成為目前這條），沒換或
  /// 不在清單裡（原生清單正被整個換掉）是 null。
  AudioStream? moved(int index) {
    if (index == _index || index < 0 || index >= _items.length) return null;
    _index = index;
    return _items[index];
  }

  /// 目前這條前面播過的要從原生清單移掉：回傳它們的位置（由大到小），並
  /// 照移掉之後記帳（目前這條變成第 0 個）。
  List<int> dropPlayed() {
    final remove = [for (var i = _index - 1; i >= 0; i--) i];
    _items.removeRange(0, _index);
    _index = 0;
    return remove;
  }
}

/// 換預載時對原生清單的改法：先依序移掉 [remove] 的位置（由大到小，前面
/// 的位置不受影響），再把 [append] 加在最後（null 是不加）。
class PreloadEdit {
  const PreloadEdit({required this.remove, required this.append});

  final List<int> remove;
  final AudioStream? append;
}

/// [BackendPlaylist.planLoad] 的結果。
sealed class LoadPlan {
  const LoadPlan();
}

/// 不是清單裡的：照常開啟，取代整個原生清單。
class Reopen extends LoadPlan {
  const Reopen();

  @override
  bool operator ==(Object other) => other is Reopen;

  @override
  int get hashCode => (Reopen).hashCode;
}

/// 預載的那條：原生跳到 [index]，不重開（事實 I4）。
class SwitchTo extends LoadPlan {
  const SwitchTo(this.index);

  final int index;

  @override
  bool operator ==(Object other) => other is SwitchTo && other.index == index;

  @override
  int get hashCode => index.hashCode;

  @override
  String toString() => 'SwitchTo($index)';
}

/// 正在放它（原生已經自己接過去了）：什麼都不做。
class AlreadyCurrent extends LoadPlan {
  const AlreadyCurrent();

  @override
  bool operator ==(Object other) => other is AlreadyCurrent;

  @override
  int get hashCode => (AlreadyCurrent).hashCode;
}
