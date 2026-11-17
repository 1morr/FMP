import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/domain/audio_stream.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/ui/toast/playback_toast.dart';

/// 播放失敗的提示依錯誤分類給文字與動作（brief〈錯誤、log 與診斷〉、
/// `docs/design/shell.html`〈手機：狀態〉）。文字以 zh-TW 為準。
void main() {
  setUp(() => LocaleSettings.setLocaleSync(AppLocale.zhTw));
  tearDown(
    () => LocaleSettings.setLocaleSync(AppLocaleUtils.instance.baseLocale),
  );

  const track = Track(
    ref: TrackRef(pluginId: 'demo', trackId: 't1'),
    title: '晴天',
    author: 'A',
  );
  final stream = AudioStream(url: Uri.parse('https://cdn.example.com/a.m4a'));

  PlaybackState failed(AppError? error, {bool resolved = false}) =>
      PlaybackState(
        track: track,
        status: PlaybackStatus.failed,
        stream: resolved ? stream : null,
        error: error,
      );

  for (final (name, state, text, icon, retry) in [
    (
      'network',
      failed(const NetworkError()),
      '沒有網路，「晴天」無法播放。音樂庫與佇列照常可用。',
      FmpIcons.wifi,
      true,
    ),
    (
      'rate limited',
      failed(const RateLimited()),
      'Demo限制了請求次數，「晴天」暫時無法播放。',
      FmpIcons.warn,
      true,
    ),
    (
      'login required',
      failed(const LoginRequired()),
      '「晴天」要登入Demo才能播放。',
      FmpIcons.warn,
      false,
    ),
    (
      'credential invalid',
      failed(const CredentialInvalid()),
      'Demo的登入已失效，「晴天」無法播放。',
      FmpIcons.warn,
      false,
    ),
    (
      'verification required',
      failed(const VerificationRequired()),
      'Demo要求驗證才能繼續播放。',
      FmpIcons.shield,
      false,
    ),
    (
      'unavailable in the region',
      failed(const Unavailable(UnavailableReason.region)),
      '「晴天」在目前的地區無法播放。',
      FmpIcons.warn,
      false,
    ),
    (
      'taken down for copyright',
      failed(const Unavailable(UnavailableReason.copyright)),
      '「晴天」因版權已下架。',
      FmpIcons.warn,
      false,
    ),
    (
      'membership required',
      failed(const Unavailable(UnavailableReason.membershipRequired)),
      '「晴天」需要會員才能播放。',
      FmpIcons.warn,
      false,
    ),
    (
      'trial only',
      failed(const Unavailable(UnavailableReason.trialOnly)),
      '「晴天」只能試聽。',
      FmpIcons.warn,
      false,
    ),
    (
      'not found',
      failed(const NotFound()),
      '找不到「晴天」，可能已被刪除。',
      FmpIcons.warn,
      false,
    ),
    (
      'parse failure',
      failed(const ParseFailure()),
      '「晴天」無法播放：讀不懂Demo的回應。',
      FmpIcons.warn,
      true,
    ),
    (
      'a source that cannot resolve streams',
      failed(const Unsupported()),
      'Demo不支援播放，「晴天」無法播放。',
      FmpIcons.warn,
      false,
    ),
    (
      'a format this device cannot play',
      failed(const Unsupported(), resolved: true),
      '這個裝置播不了「晴天」的格式。',
      FmpIcons.warn,
      false,
    ),
    ('a program error', failed(null), '「晴天」無法播放。', FmpIcons.warn, true),
  ]) {
    test('$name: ${retry ? 'offers a retry' : 'no action'}', () {
      var retried = 0;
      final toast = playbackFailedToast(
        t,
        state,
        source: 'Demo',
        retry: () => retried++,
      );

      expect(toast.text, text);
      expect(toast.icon, icon);
      if (retry) {
        expect(toast.action!.label, '重試');
        toast.action!.onTap();
        expect(retried, 1);
      } else {
        expect(toast.action, isNull);
      }
    });
  }
}
