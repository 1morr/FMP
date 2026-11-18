import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/playback/queue_controller.dart';
import 'package:fmp/ui/toast/toast.dart';

/// 播放失敗的提示（`docs/design/shell.html`〈手機：狀態〉）：依錯誤分類寫出
/// 哪一首、為什麼，再接佇列怎麼處理。跳下一首、回到佇列時不帶動作；連續
/// 幾首都播不了而停止時寫在前面，動作是「看佇列」[showQueue]；停在這首時
/// 重試有機會成功的類別（網路、限流、解析失敗、原因不明）帶「重試」[retry]，
/// 登入與驗證的動作等那些功能做出來才加。[source] 是音源名稱（manifest 的
/// `name`）。
ToastMessage playbackFailedToast(
  Translations t,
  PlaybackFailure failure, {
  required String source,
  required void Function() retry,
  required void Function() showQueue,
}) {
  final reason = _reasonToast(t, failure.state, source: source, retry: retry);
  final s = t.toast.playback;
  return switch (failure.outcome) {
    FailureOutcome.stayed => reason,
    FailureOutcome.skipped => ToastMessage(
      s.skipped(reason: reason.text),
      icon: reason.icon,
    ),
    FailureOutcome.returnedToQueue => ToastMessage(
      s.returnedToQueue(reason: reason.text),
      icon: reason.icon,
    ),
    FailureOutcome.stopped => ToastMessage(
      s.stopped(count: failure.streak, reason: reason.text),
      icon: reason.icon,
      action: ToastAction(t.toast.showQueue, showQueue),
    ),
  };
}

/// 只講這一首為什麼播不了的提示。
ToastMessage _reasonToast(
  Translations t,
  PlaybackState state, {
  required String source,
  required void Function() retry,
}) {
  final s = t.toast.playback;
  final title = state.track.title;
  final retryAction = ToastAction(t.toast.retry, retry);
  return switch (state.error) {
    NetworkError() => ToastMessage(
      s.network(title: title),
      icon: FmpIcons.wifi,
      action: retryAction,
    ),
    RateLimited() => ToastMessage(
      s.rateLimited(title: title, source: source),
      icon: FmpIcons.warn,
      action: retryAction,
    ),
    LoginRequired() => ToastMessage(
      s.loginRequired(title: title, source: source),
      icon: FmpIcons.warn,
    ),
    CredentialInvalid() => ToastMessage(
      s.credentialInvalid(title: title, source: source),
      icon: FmpIcons.warn,
    ),
    VerificationRequired() => ToastMessage(
      s.verificationRequired(source: source),
      icon: FmpIcons.shield,
    ),
    Unavailable(:final reason) => ToastMessage(switch (reason) {
      UnavailableReason.region => s.region(title: title),
      UnavailableReason.copyright => s.copyright(title: title),
      UnavailableReason.membershipRequired => s.membership(title: title),
      UnavailableReason.trialOnly => s.trialOnly(title: title),
    }, icon: FmpIcons.warn),
    NotFound() => ToastMessage(s.notFound(title: title), icon: FmpIcons.warn),
    ParseFailure() => ToastMessage(
      s.parseFailure(title: title, source: source),
      icon: FmpIcons.warn,
      action: retryAction,
    ),
    // 還沒有串流是插件不支援解析，有了是這個平台播不了那個格式。
    Unsupported() => ToastMessage(
      state.stream == null
          ? s.sourceUnsupported(title: title, source: source)
          : s.formatUnsupported(title: title),
      icon: FmpIcons.warn,
    ),
    null => ToastMessage(
      s.failed(title: title),
      icon: FmpIcons.warn,
      action: retryAction,
    ),
  };
}
