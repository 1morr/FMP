import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/ui/errors/error_message.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/plugins/plugin_name.dart';

/// 提示的語意（ADR 0023 §決定 2）：決定顏色、圖示與時長。
enum ToastKind {
  success,
  info,
  warning,
  error;

  /// 自動消失前停留多久：成功與資訊 4 秒，警告與錯誤 6 秒。
  Duration get duration => switch (this) {
    success || info => const Duration(seconds: 4),
    warning || error => const Duration(seconds: 6),
  };
}

/// 提示上的動作；每則最多一個（ADR 0023 §決定 1）。[label] 是翻譯過的字串。
@immutable
final class ToastAction {
  const ToastAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;
}

/// 一則要顯示的提示；[message] 已經是翻譯過的文字。
@immutable
final class Toast {
  const Toast({required this.kind, required this.message, this.action});

  final ToastKind kind;
  final String message;
  final ToastAction? action;
}

/// App 唯一的提示入口（ADR 0023 §決定 1），以 [toasterProvider] 取得，不需要
/// `BuildContext`。
///
/// 只給使用者動作的回饋用；背景工作不呼叫它，只更新對應畫面的狀態。它不畫
/// 任何東西：去重之後把 [Toast] 送進 [toasts]，由 `ToastHost` 顯示。
final class Toaster {
  Toaster({
    required this._log,
    required this._translations,
    required this._sourceName,
  });

  /// 同一類提示在這段時間內只顯示一次（ADR 0013 §決定 5 的「短時間」）。
  static const dedupeWindow = Duration(seconds: 5);

  final Log _log;
  final Translations Function() _translations;
  final String? Function(String pluginId) _sourceName;

  final _toasts = StreamController<Toast>.broadcast(sync: true);
  final _lastShown = <Object, DateTime>{};

  /// 通過去重的提示。沒有 `ToastHost` 在聽時就丟掉。
  Stream<Toast> get toasts => _toasts.stream;

  /// [message] 是翻譯過的字串（`translationsProvider`）。
  void success(String message, {ToastAction? action}) =>
      _message(ToastKind.success, message, action);

  void info(String message, {ToastAction? action}) =>
      _message(ToastKind.info, message, action);

  void warning(String message, {ToastAction? action}) =>
      _message(ToastKind.warning, message, action);

  /// 使用者動作失敗。先經 `log.report` 寫進錯誤歷史（不論之後有沒有被去重
  /// 掉），再依 ADR 0013 的類別表顯示翻譯過的訊息；只收 [AppError]，所以
  /// 例外或伺服器的原文上不了畫面。
  ///
  /// [operation] 是失敗的動作（英文，例如 `'Search failed'`），[tag] 是模組
  /// 或音源 id，比照 `log.report`。去重以「錯誤類別＋音源」為鍵。
  ///
  /// [sentence] 把錯誤訊息放進一句翻譯過的話（例如「已跳過「歌名」：訊息」），
  /// 收到的是依類別表翻譯好的訊息；沒給就只顯示訊息。
  void error(
    AppError error, {
    required String operation,
    required String tag,
    String Function(String message)? sentence,
    ToastAction? action,
  }) {
    _log.report(operation, error, tag: tag);
    final pluginId = error.pluginId;
    final message = errorMessage(
      _translations(),
      error,
      sourceName: pluginId == null ? null : _sourceName(pluginId) ?? pluginId,
    );
    _show(
      Toast(
        kind: ToastKind.error,
        message: sentence == null ? message : sentence(message),
        action: action,
      ),
      key: _errorKey(error),
    );
  }

  /// [pluginId] 的登入被音源拒絕、轉成已失效（`AccountGuard` 的事件）：以警告顯示
  /// [message] 與「登入」[action]，並佔住 [CredentialInvalid]＋該音源的錯誤去重鍵。
  ///
  /// 守衛先標失效、發事件，原呼叫的錯誤才往上：同一個失敗接著從搜尋、播放以 [error]
  /// 送來時就被去重掉，不會把這則換成沒有「登入」的錯誤提示（ADR 0013 §決定 5：刷新
  /// 失敗才提示一次需重新登入）。錯誤歷史照常由 [error] 寫。這則本身不看那個鍵：就算
  /// 錯誤提示先到，也由它換掉。
  void credentialInvalidated(
    String pluginId,
    String message, {
    required ToastAction action,
  }) {
    _show(
      Toast(kind: ToastKind.warning, message: message, action: action),
      key: (ToastKind.warning, message),
    );
    _lastShown[_errorKey(CredentialInvalid(pluginId: pluginId))] = clock.now();
  }

  static Object _errorKey(AppError error) => (error.typeName, error.pluginId);

  void _message(ToastKind kind, String message, ToastAction? action) => _show(
    Toast(kind: kind, message: message, action: action),
    key: (kind, message),
  );

  void _show(Toast toast, {required Object key}) {
    final now = clock.now();
    _lastShown.removeWhere((_, shown) => now.difference(shown) >= dedupeWindow);
    if (_lastShown.containsKey(key)) return;
    _lastShown[key] = now;
    _toasts.add(toast);
  }

  void dispose() => _toasts.close();
}

/// App 的 [Toaster]。錯誤訊息用目前的介面語言，音源名稱取插件 manifest 的
/// `name`（`pluginNameProvider`；未安裝、停用的有自己的字樣），清單還沒載入完時用
/// `pluginId`（manifest 驗過格式）。
final toasterProvider = Provider<Toaster>((ref) {
  final toaster = Toaster(
    log: ref.watch(logProvider),
    translations: () => ref.read(translationsProvider),
    sourceName: (pluginId) => ref.read(pluginNameProvider(pluginId)),
  );
  ref.onDispose(toaster.dispose);
  return toaster;
});
