/// 播放的音質偏好（「播放」設定組，design §3.3）。由插件依它挑串流（M2 PR 8）。
///
/// 放在 `domain/`：資料層要存它（字串寫死在資料層的轉換裡，不用 [name]）。
enum AudioQuality { high, medium, low }

/// 播放的格式偏好：哪一種編碼優先（「播放」設定組，design §3.3）。宿主依它
/// 重排平台可播的格式再交給插件（M2 PR 8）。
enum AudioFormatPriority { opusFirst, aacFirst }
