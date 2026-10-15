package com.personal.fmp;

import android.content.Intent;
import android.os.Bundle;
import android.util.Log;
import android.view.KeyEvent;
import android.support.v4.media.session.MediaSessionCompat;

import com.ryanheise.audioservice.AudioService;

import java.lang.ref.WeakReference;
import java.lang.reflect.Field;

// audio_service 0.18.19 把真正的 KEYCODE_MEDIA_PLAY / KEYCODE_MEDIA_PAUSE 都轉成
// MediaButton.media，Dart 端的 click 再切換，所以已暫停時收到「暫停」鍵會開始播放
// （#233）。套件自己的通知按鈕用 KEYCODE_BYPASS_PLAY / KEYCODE_BYPASS_PAUSE，
// 會直接走 onPlay / onPause。這裡把真正的 PLAY / PAUSE 改成 BYPASS 版本，
// PLAY_PAUSE 與 HEADSETHOOK 維持切換。
//
// 用 Java 寫：MediaSessionCallback 是 AudioService 的 inner class，Kotlin 在外部
// 不能繼承它，Java 才有 `outer.new Inner() {}`。依賴套件的私有欄位 mediaSession、
// mediaSessionCallback 與套件私有的靜態 instance，升級 audio_service 時要重查
// （test/platform/audio_service_internals_test.dart 釘版）；R8 的 keep 規則在
// proguard-rules.pro。沒有自動閘門，改動後要在 Android 實機驗（adb shell input
// keyevent KEYCODE_MEDIA_PAUSE / KEYCODE_MEDIA_PLAY）。
final class MediaKeyFix {
    private static final String TAG = "MediaKeyFix";

    // 我們裝上去的 callback；服務重建後 callback 是新的，比對不到就會再裝一次。
    private static WeakReference<Object> installed = new WeakReference<>(null);

    private MediaKeyFix() {}

    /**
     * 把 audio_service 的 media session callback 換成會改寫鍵碼的版本。
     * 已經換過回傳 true（可重複呼叫）；服務還沒建立或反射失敗回傳 false，不丟例外。
     */
    static synchronized boolean install() {
        try {
            final Field instanceField = AudioService.class.getDeclaredField("instance");
            instanceField.setAccessible(true);
            final AudioService service = (AudioService) instanceField.get(null);
            if (service == null) return false;

            final Field callbackField = AudioService.class.getDeclaredField("mediaSessionCallback");
            callbackField.setAccessible(true);
            final Object current = callbackField.get(service);
            if (current != null && current == installed.get()) return true;

            final Field sessionField = AudioService.class.getDeclaredField("mediaSession");
            sessionField.setAccessible(true);
            final MediaSessionCompat session = (MediaSessionCompat) sessionField.get(service);
            if (session == null) return false;

            // 其餘方法全部沿用套件的實作，只改寫媒體鍵。
            final AudioService.MediaSessionCallback callback = service.new MediaSessionCallback() {
                @Override
                public boolean onMediaButtonEvent(Intent mediaButtonEvent) {
                    return super.onMediaButtonEvent(rewrite(mediaButtonEvent));
                }
            };
            installed = new WeakReference<>(callback);
            session.setCallback(callback);
            // 服務其他地方會呼叫 mediaSessionCallback.onPlayMediaItem，要同步換掉。
            callbackField.set(service, callback);
            return true;
        } catch (ReflectiveOperationException | RuntimeException e) {
            Log.w(TAG, "Could not install the media key fix", e);
            return false;
        }
    }

    static Intent rewrite(Intent intent) {
        final Bundle extras = intent == null ? null : intent.getExtras();
        if (extras == null) return intent;
        @SuppressWarnings("deprecation") // 取得型別安全版本要 SDK 33，套件也是這樣讀
        final KeyEvent event = extras.getParcelable(Intent.EXTRA_KEY_EVENT);
        if (event == null) return intent;
        final int code;
        switch (event.getKeyCode()) {
            case KeyEvent.KEYCODE_MEDIA_PLAY:
                code = AudioService.KEYCODE_BYPASS_PLAY;
                break;
            case KeyEvent.KEYCODE_MEDIA_PAUSE:
                code = AudioService.KEYCODE_BYPASS_PAUSE;
                break;
            default:
                return intent;
        }
        final KeyEvent rewritten = new KeyEvent(
                event.getDownTime(), event.getEventTime(), event.getAction(), code,
                event.getRepeatCount(), event.getMetaState(), event.getDeviceId(),
                event.getScanCode(), event.getFlags(), event.getSource());
        return new Intent(intent).putExtra(Intent.EXTRA_KEY_EVENT, rewritten);
    }
}
