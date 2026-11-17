import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/ui/toast/toast.dart';

/// 播放失敗的提示：依錯誤分類寫出哪一首、為什麼（`docs/design/shell.html`
/// 〈手機：狀態〉）。重試有機會成功的類別（網路、限流、解析失敗、原因不明）
/// 帶「重試」[retry]；登入與驗證的動作等那些功能做出來才加。[source] 是
/// 音源名稱（manifest 的 `name`）。
ToastMessage playbackFailedToast(
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
