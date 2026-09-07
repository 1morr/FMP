import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 補上 `showLicensePage()` 看不到的第三方授權。
///
/// Flutter 內建的授權頁只收錄 **pub 套件目錄裡的 `LICENSE` 檔**。Windows 上
/// 真正播放音訊的 `libmpv-2.dll` 是 `media_kit_libs_windows_audio` 在建置時
/// 才下載的二進位，它的 LGPL 授權文字因此完全不會出現在那一頁 —— 這個缺口
/// 與 FMP 自己用什麼授權無關，早在切 MIT 之前就成立。
///
/// 出處、建置旗標的第一手查證與四個合規條件見 `THIRD_PARTY_LICENSES.md`。
void registerThirdPartyLicenses() =>
    LicenseRegistry.addLicense(thirdPartyLicenses);

/// [registerThirdPartyLicenses] 交給 [LicenseRegistry] 的收集器。
///
/// 公開是為了讓測試不必動到全域的 [LicenseRegistry] —— 那是行程層級的狀態，
/// 一旦在測試裡登記就再也拿不掉。
Stream<LicenseEntry> thirdPartyLicenses() async* {
  yield const LicenseEntryWithLineBreaks([
    'Protocol research',
  ], _protocolResearchNotice);

  // Android 走 just_audio / ExoPlayer，整包裡沒有 libmpv。在那裡列出它會
  // 讓使用者以為裝置上有一個不存在的元件。
  if (!Platform.isWindows) return;

  yield LicenseEntryWithLineBreaks(
    _mpvPackages,
    '$_mpvNotice\n\n${await _text('LGPL-2.1')}',
  );
  yield LicenseEntryWithLineBreaks(_mpvPackages, await _text('LGPL-3.0'));
  // LGPL-3.0 是寫在 GPL-3.0 之上的一組附加許可，單獨給它並不完整。
  yield LicenseEntryWithLineBreaks(_mpvPackages, await _text('GPL-3.0'));
}

const _mpvPackages = ['libmpv / FFmpeg'];

Future<String> _text(String name) =>
    rootBundle.loadString('licenses/$name.txt');

const _protocolResearchNotice = '''
FMP reaches Bilibili, YouTube, NetEase Cloud Music and QQ Music through private
APIs. Endpoint shapes, signing steps and protocol constants come from public
reverse-engineering write-ups rather than from any project's source code.

bilibili-API-collect (https://github.com/SocialSisterYi/bilibili-API-collect)
is licensed CC BY-NC 4.0. It documents the Bilibili endpoints, the WBI signing
steps and the cookie-refresh public key.

netease-cloud-music (https://github.com/chaunsin/netease-cloud-music) is
licensed MIT and was used as a reference for the NetEase request format.

See THIRD_PARTY_LICENSES.md in the source repository for the full record.''';

const _mpvNotice = '''
libmpv-2.dll is the audio backend media_kit uses on Windows. It is not part of
any pub package: media_kit_libs_windows_audio downloads a prebuilt archive from
https://github.com/media-kit/libmpv-win32-audio-build during the build.

That build excludes every GPL-only component (mpv is built with -Dgpl=false and
FFmpeg with --disable-gpl --disable-nonfree --enable-version3), so it is
LGPL-2.1-or-later, with the LGPL-3 components that --enable-version3 enables.

FMP links it dynamically and ships it as a separate file, so it can be replaced
with a modified build without rebuilding FMP. Sources are available from
https://github.com/mpv-player/mpv and https://github.com/FFmpeg/FFmpeg.''';
