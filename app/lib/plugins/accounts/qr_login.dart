import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/plugins/accounts/account_service.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/plugins/source_plugin.dart';

/// QR 畫面開著時多久問一次進度（舊版的間隔，design §4.3）。
const qrPollInterval = Duration(seconds: 2);

/// QR 登入走到哪一步（[QrLogin.value]）。
sealed class QrLoginState {
  const QrLoginState();
}

/// 正在向插件要 QR 碼。
final class QrLoginStarting extends QrLoginState {
  const QrLoginStarting();
}

/// QR 碼顯示中；[scanned] 是使用者已經掃了、還沒在手機上確認。
final class QrLoginShowing extends QrLoginState {
  const QrLoginShowing(this.qrText, {required this.scanned});

  final String qrText;
  final bool scanned;
}

/// QR 碼過期了，等使用者按「重新產生」（[QrLogin.start]）。[qrText] 是過期的那一個
/// （畫面蓋上遮罩照樣畫出來）。
final class QrLoginExpired extends QrLoginState {
  const QrLoginExpired(this.qrText);

  final String qrText;
}

/// 手機上確認了，正在驗證並寫入憑證（[AccountService.login]）。
final class QrLoginVerifying extends QrLoginState {
  const QrLoginVerifying();
}

/// 登入完成。
final class QrLoginDone extends QrLoginState {
  const QrLoginDone(this.account);

  final Account account;
}

/// 產生、輪詢或驗證失敗（已經 `log.report`）；[QrLogin.start] 重來。
final class QrLoginFailed extends QrLoginState {
  const QrLoginFailed(this.error);

  final AppError error;
}

/// 一次 QR 登入（design §6.4）：`loginQrStart` → 每 [qrPollInterval] 問一次
/// `loginQrPoll`（一次性 `Timer` 接力，上一次回來才排下一次，不是週期計時器）→
/// `done` 時交 [AccountService.login]（驗證通過才寫入）。
///
/// QR 畫面持有它、離開時 [dispose]：計時器取消，進行中的呼叫回來後丟掉、不再排下一次。
/// [start] 重新產生時，上一個 QR 碼的結果同樣丟掉。手機上已經確認、正在驗證時離開，
/// 驗證照樣跑完並寫入（使用者已經同意登入）。
final class QrLogin extends ValueNotifier<QrLoginState> {
  QrLogin({
    required this._plugin,
    required this._accounts,
    required this._log,
    this._interval = qrPollInterval,
  }) : super(const QrLoginStarting());

  final SourcePlugin _plugin;
  final AccountService _accounts;
  final Log _log;
  final Duration _interval;

  Timer? _timer;

  /// 每次 [start] 加一：舊的 QR 碼與離開後的結果靠它認出來丟掉。
  int _generation = 0;
  var _disposed = false;

  /// 向插件要一個新的 QR 碼並開始輪詢；已經在跑的那一個作廢。
  Future<void> start() async {
    if (_disposed) return;
    final generation = ++_generation;
    _timer?.cancel();
    _timer = null;
    value = const QrLoginStarting();
    final LoginQrCode code;
    try {
      code = await _plugin.loginQrStart();
    } on Object catch (error, stackTrace) {
      _fail(generation, error, stackTrace);
      return;
    }
    if (!_isCurrent(generation)) return;
    value = QrLoginShowing(code.qrText, scanned: false);
    _schedule(generation, code);
  }

  void _schedule(int generation, LoginQrCode code) {
    _timer = Timer(_interval, () => unawaited(_poll(generation, code)));
  }

  Future<void> _poll(int generation, LoginQrCode code) async {
    _timer = null;
    final LoginQrPoll poll;
    try {
      poll = await _plugin.loginQrPoll(code.token);
    } on Object catch (error, stackTrace) {
      _fail(generation, error, stackTrace);
      return;
    }
    if (!_isCurrent(generation)) return;
    switch (poll.status) {
      case LoginQrStatus.waiting || LoginQrStatus.scanned:
        value = QrLoginShowing(
          code.qrText,
          scanned: poll.status == LoginQrStatus.scanned,
        );
        _schedule(generation, code);
      case LoginQrStatus.expired:
        value = QrLoginExpired(code.qrText);
      case LoginQrStatus.done:
        value = const QrLoginVerifying();
        try {
          final account = await _accounts.login(_plugin, poll.credentials!);
          if (_isCurrent(generation)) value = QrLoginDone(account);
        } on Object catch (error, stackTrace) {
          _fail(generation, error, stackTrace);
        }
    }
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _fail(int generation, Object error, StackTrace stackTrace) {
    final appError = AppError.wrap(
      error,
      stackTrace,
      pluginId: _plugin.manifest.id,
    );
    // 離開或重新產生之後的失敗也記下（錯誤歷史），只是不再顯示。
    _log.report('QR login failed', appError, tag: 'accounts');
    if (_isCurrent(generation)) value = QrLoginFailed(appError);
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
