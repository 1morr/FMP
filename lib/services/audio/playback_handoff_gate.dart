import 'dart:async';

import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';

/// 一個被延後的 seek。
///
/// 身分靠物件同一性判定 —— [PlaybackHandoffGate._applyPendingIfCurrent] 在
/// `await` 之後會重新確認手上的還是同一個物件，用來擋掉等待期間被取代的情況。
/// **不要給它加 `==`**：同一個請求上跳到同一個位置的兩次 seek 會因此變得無法
/// 區分，舊的那次就會被當成新的套用。
class _PendingSeek {
  _PendingSeek({
    required this.position,
    required this.trackKey,
    required this.requestId,
  });

  final Duration position;
  final String trackKey;
  final int requestId;
  final Completer<void> _completer = Completer<void>();

  Future<void> get future => _completer.future;

  void complete() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }
}

/// 切歌之後的短暫穩定化視窗。
class _StabilizationWindow {
  const _StabilizationWindow({
    required this.requestId,
    required this.trackKey,
    required this.until,
  });

  final int requestId;
  final String trackKey;
  final DateTime until;
}

/// 擁有「控制器正在交接一次播放請求」這段期間的狀態。
///
/// 兩件事合在同一個類別裡，因為它們在既有程式碼裡**沒有一次是分開改的**：
/// 載入閂存（[activeRequestId]）的每一次寫入都伴隨一次延後 seek 的寫入，反之
/// 亦然。分成兩個類別只會讓其中一邊必須拿著另一邊的參照，然後把「記得兩邊一起
/// 改」這條紀律再留給呼叫端 —— 那正是步驟 D 在 Mix 上消掉的 bug 形狀。
///
/// **[activeRequestId] 不是第二個請求計數器。** 它是 `PlaybackRequestSession`
/// 那個單調遞增 id 的閂存副本：`_enterLoading()` 產生 id 後經 `onLoadingStarted`
/// 原樣傳進 [beginRequest]，交接結束由 [endRequest] 歸零。它回答的是「控制器現在
/// 正在為哪一次請求做投影」，不是「哪一次請求才是最新的」—— 後者要問
/// `isRequestSuperseded`。
///
/// **它不碰 `PlayerState`。** 需要的只有目前播放中那首歌的 key，由建構子的
/// `currentTrackKey` 回呼讀進來；`isLoading` 的投影留在 `AudioController`，
/// 與 `QueueCommands` / `MixSessionCoordinator` 同一條規矩。
///
/// **它不執行 seek。** 真正的 seek 要動緩衝看門狗、音訊後端與佇列持久化，三個
/// 都不該被一個只管「什麼時候」的類別持有，所以由 `performSeek` 回呼傳進來。
class PlaybackHandoffGate with Logging {
  PlaybackHandoffGate({
    required String? Function() currentTrackKey,
    required Future<void> Function(Duration position) performSeek,
    required bool Function(int requestId) isRequestSuperseded,
    Duration stabilizationDelay = AppConstants.seekStabilizationDelay,
  })  : _currentTrackKey = currentTrackKey,
        _performSeek = performSeek,
        _isRequestSuperseded = isRequestSuperseded,
        _stabilizationDelay = stabilizationDelay;

  final String? Function() _currentTrackKey;
  final Future<void> Function(Duration position) _performSeek;
  final bool Function(int requestId) _isRequestSuperseded;
  final Duration _stabilizationDelay;

  int _activeRequestId = 0;
  _PendingSeek? _pending;
  _StabilizationWindow? _window;
  bool _stabilizeNextRequest = false;

  /// 控制器正在投影哪一次請求的交接，0 代表不在交接中。
  int get activeRequestId => _activeRequestId;

  bool get isLoading => _activeRequestId > 0;

  /// 這一次交接是不是控制器手上那一次。
  ///
  /// 刻意與 `isRequestSuperseded` 不同：那個問的是 session 的世代，這個問的是
  /// 控制器的閂存。`_clearMatchingSessionLoadingContext` 是唯一以閂存為準的
  /// 路徑，兩者不可互換。
  bool isCurrent(int requestId) => _activeRequestId == requestId;

  // ========== 交接生命週期 ==========

  /// 一次新的播放請求即將進入載入狀態。
  ///
  /// 只清穩定化視窗與延後中的 seek，**刻意不清 [_stabilizeNextRequest]** ——
  /// 那個旗標由 `next()` / `previous()` / `playAt()` 設下，要留到
  /// `_executePlayRequest` 去取用。[cancel] 才會連它一起清掉。
  void prepareForRequest({required String reason}) {
    _window = null;
    discardPending(reason: reason);
  }

  void beginRequest(int requestId) {
    _activeRequestId = requestId;
  }

  void endRequest() {
    _activeRequestId = 0;
  }

  /// 使用者主動開了另一條播放路徑（單曲 / 臨時 / 佇列 / Mix）。
  /// 上一次交接的所有殘留一次收乾淨。
  void cancel({required String reason}) {
    discardPending(reason: reason);
    _clearStabilizationWindow();
    _activeRequestId = 0;
  }

  /// 只丟掉延後中的 seek 與穩定化視窗，**不動閂存** —— `stop()` 用這條。
  void cancelDeferredSeeks({required String reason}) {
    discardPending(reason: reason);
    _clearStabilizationWindow();
  }

  // ========== seek 延後 ==========

  /// 決定這次 seek 要不要延後。
  ///
  /// 回傳 null 代表「現在就送給後端」；回傳 future 代表已經接下了，呼叫端 await
  /// 它即可 —— 無論最後是套用還是作廢，這個 future 都會完成，不會 hang。
  Future<void>? deferSeek(Duration position) {
    return _deferWhileLoading(position) ?? _deferWhileStabilizing(position);
  }

  Future<void>? _deferWhileLoading(Duration position) {
    final requestId = _activeRequestId;
    if (requestId <= 0) return null;

    final trackKey = _currentTrackKey();
    if (trackKey == null) return null;

    discardPending(reason: 'newer seek queued during playback handoff');
    final pending = _PendingSeek(
      position: position,
      trackKey: trackKey,
      requestId: requestId,
    );
    _pending = pending;
    logDebug(
      'Deferring seek to $position until playback request $requestId is ready',
    );
    return pending.future;
  }

  Future<void>? _deferWhileStabilizing(Duration position) {
    final window = _window;
    if (window == null) return null;

    final trackKey = _currentTrackKey();
    final remaining = _remainingStabilizationDelay(
      requestId: window.requestId,
      trackKey: window.trackKey,
    );
    if (remaining <= Duration.zero ||
        trackKey != window.trackKey ||
        _isRequestSuperseded(window.requestId)) {
      _clearStabilizationWindow();
      return null;
    }

    discardPending(reason: 'newer seek queued during seek stabilization');
    final pending = _PendingSeek(
      position: position,
      trackKey: window.trackKey,
      requestId: window.requestId,
    );
    _pending = pending;
    logDebug(
      'Deferring seek to $position for $remaining after playback request ${window.requestId}',
    );
    applyPendingIfCurrent(window.requestId);
    return pending.future;
  }

  /// 這次請求準備好了，把它身上延後的 seek 送出去。不阻塞呼叫端。
  void applyPendingIfCurrent(int requestId) {
    unawaited(_applyPendingIfCurrent(requestId));
  }

  Future<void> _applyPendingIfCurrent(int requestId) async {
    final pending = _pending;
    if (pending == null || pending.requestId != requestId) return;

    final stabilizationDelay = _remainingStabilizationDelay(
      requestId: requestId,
      trackKey: pending.trackKey,
    );
    if (stabilizationDelay > Duration.zero) {
      logDebug(
        'Waiting $stabilizationDelay before applying deferred seek for request $requestId',
      );
      await Future<void>.delayed(stabilizationDelay);
      // 等待期間可能被更新的 seek 取代。比的是物件同一性，見 _PendingSeek。
      if (_pending != pending) return;
    }

    if (_isRequestSuperseded(requestId) ||
        _currentTrackKey() != pending.trackKey) {
      discardPending(
        requestId: requestId,
        reason: 'pending seek no longer matches current track',
      );
      return;
    }

    _pending = null;
    logDebug(
      'Applying deferred seek to ${pending.position} for request $requestId',
    );
    try {
      await _performSeek(pending.position);
    } catch (e, stack) {
      logError(
          'Failed to apply deferred seek to ${pending.position}', e, stack);
    } finally {
      pending.complete();
    }
  }

  /// 丟掉延後中的 seek。
  ///
  /// 給了 [requestId] 就只丟屬於那次請求的。無論走哪一條，被丟掉的 seek 一定會
  /// `complete()` —— 呼叫 `seekTo` 的人正在 await 它。
  void discardPending({int? requestId, required String reason}) {
    final pending = _pending;
    if (pending == null) return;
    if (requestId != null && pending.requestId != requestId) return;
    _pending = null;
    logDebug(
      'Discarding deferred seek to ${pending.position} for request ${pending.requestId}: $reason',
    );
    pending.complete();
  }

  // ========== 穩定化視窗 ==========

  /// 下一次播放請求 ready 之後要開穩定化視窗。
  ///
  /// 由 `next()` / `previous()` / `playAt()` 設下 —— 使用者連按切歌時，後端剛
  /// 開好流的那一小段時間裡的 seek 要等它站穩再送。
  void requestStabilizationForNextRequest() {
    _stabilizeNextRequest = true;
  }

  bool consumeStabilizationForNextRequest() {
    final shouldStabilize = _stabilizeNextRequest;
    _stabilizeNextRequest = false;
    return shouldStabilize;
  }

  void startStabilizationWindow(int requestId, String trackKey) {
    final until = DateTime.now().add(_stabilizationDelay);
    _window = _StabilizationWindow(
      requestId: requestId,
      trackKey: trackKey,
      until: until,
    );
    logDebug('Stabilizing seeks for request $requestId until $until');
  }

  /// 視窗還剩多久。過期時順手清掉 —— 這個副作用是刻意的，別改成純查詢。
  Duration _remainingStabilizationDelay({
    required int requestId,
    required String trackKey,
  }) {
    final window = _window;
    if (window == null ||
        window.requestId != requestId ||
        window.trackKey != trackKey) {
      return Duration.zero;
    }

    final remaining = window.until.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      _window = null;
      return Duration.zero;
    }
    return remaining;
  }

  void _clearStabilizationWindow() {
    _window = null;
    _stabilizeNextRequest = false;
  }

  void dispose() {
    discardPending(reason: 'controller disposed');
    _clearStabilizationWindow();
  }
}
