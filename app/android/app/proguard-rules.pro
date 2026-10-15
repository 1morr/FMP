# MediaKeyFix.java 用反射讀 audio_service 的私有欄位（#233）。名稱被 R8 改掉，
# 反射就失敗，媒體鍵回到會切換的舊行為。釘版測試：
# test/platform/audio_service_internals_test.dart。
-keepclassmembers class com.ryanheise.audioservice.AudioService {
    static com.ryanheise.audioservice.AudioService instance;
    private android.support.v4.media.session.MediaSessionCompat mediaSession;
    private com.ryanheise.audioservice.AudioService$MediaSessionCallback mediaSessionCallback;
}
-keep class com.ryanheise.audioservice.AudioService$MediaSessionCallback { *; }
