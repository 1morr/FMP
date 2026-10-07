/// 速度的範圍與播放頁「⋯」選單的選項（舊版 `app_constants.dart` 的選項
/// 0.5–2.0，design §7.6）。
const minSpeed = 0.5;
const maxSpeed = 2.0;

/// 播放頁選單的速度選項。
const speedOptions = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

/// 夾到 [minSpeed]–[maxSpeed]：控制器與兩個後端在交給引擎之前都經過它。
double clampSpeed(double speed) => speed.clamp(minSpeed, maxSpeed).toDouble();
