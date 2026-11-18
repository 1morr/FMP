package com.personal.fmp.dev

import com.ryanheise.audioservice.AudioServiceActivity

// audio_service 的前景服務和這個 Activity 共用同一個 FlutterEngine：關掉畫面
// （按返回、從最近使用滑掉）後 Dart 照常在背景播放（audio_service 的 README
// 〈Custom Android activity〉）。
class MainActivity : AudioServiceActivity()
