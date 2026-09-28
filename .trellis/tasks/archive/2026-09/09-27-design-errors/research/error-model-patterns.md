# 統一錯誤模型前置研究（一）：官方架構建議與型別設計

本檔涵蓋研究項目 1–3：Flutter 官方 App Architecture 的錯誤處理建議、Riverpod（含 Riverpod 3
自動重試）的錯誤處理慣例、Dart `sealed class` 慣例與錯誤欄位設計。查證方式：官方文件
（docs.flutter.dev、dart.dev、riverpod.dev）與 context7 鏡像的官方原始碼／文件。查不到的地方
標「查不到」，推論的地方標「推測」。

## 1. Flutter 官方 App Architecture：`Result` 與 `Command`

來源：<https://docs.flutter.dev/app-architecture/design-patterns/result>、
<https://docs.flutter.dev/app-architecture/design-patterns/command>（皆為官方文件，範例取自
`flutter/samples` 的 Compass App）。

### 1.1 為什麼 repository／service 回傳 `Result` 而不丟例外

官方文件的論點（逐條對應原文）：

- **Dart 的例外是 unchecked**：「methods that throw exceptions don't need to declare them, and
  calling methods aren't required to catch them either」——呼叫方沒有編譯期義務處理例外。
- **例外會在跨層呼叫中被漏接**：在 service → repository → view model 的鏈路中，view model 不會
  直接呼叫 service；忘記包 `try-catch` 的 view model「compiles and runs, but crashes」，直到真的
  觸發網路／JSON／HTTP 錯誤才會爆炸。
- **`Result` 把錯誤放進回傳型別**：「`Result` classes force the calling method to check for
  errors, reducing the amount of bugs caused by uncaught exceptions.」
- **控制流變簡單**：多層 fallback 不需要巢狀 `try-catch`，改用型別檢查（`if (apiResult is Ok)
  return apiResult;`）依序嘗試。

### 1.2 完整程式碼（原文逐字，來自官方文件）

```dart
/// Utility class that simplifies handling errors.
///
/// Return a [Result] from a function to indicate success or failure.
///
/// A [Result] is either an [Ok] with a value of type [T]
/// or an [Error] with an [Exception].
sealed class Result<T> {
  const Result();

  const factory Result.ok(T value) = Ok._;
  const factory Result.error(Exception error) = Error._;
}

final class Ok<T> extends Result<T> {
  const Ok._(this.value);
  final T value;
}

final class Error<T> extends Result<T> {
  const Error._(this.error);
  final Exception error;
}
```

服務層產生 `Result`（把 `throw` 換成 `Result.error`，並把可能丟出的例外收進 `catch`）：

```dart
Future<Result<UserProfile>> getUserProfile() async {
  try {
    final response = await client.get(...);
    if (response.statusCode == 200) {
      return Result.ok(UserProfile.fromJson(jsonDecode(...)));
    } else {
      return const Result.error(HttpException('Invalid response'));
    }
  } on Exception catch (exception) {
    return Result.error(exception);
  }
}
```

呼叫方用窮舉 `switch` 拆解（`sealed` 保證編譯期檢查兩種分支都處理到）：

```dart
switch (result) {
  case Ok<UserProfile>():
    userProfile = result.value;
  case Error<UserProfile>():
    error = result.error;
}
```

官方文件也列出現成套件作為 `Result` 的替代實作：`result_dart`、`result_type`、
`multiple_result`（三者均為 pub.dev 上的套件，文件未評比優劣）。

### 1.3 `Command` 如何把錯誤／loading 狀態暴露給 UI

`Command`／`Command0`／`Command1` 包一個回傳 `Result<T>` 的函式，繼承 `ChangeNotifier`：

```dart
abstract class Command<T> extends ChangeNotifier {
  bool _running = false;
  bool get running => _running;

  Result<T>? _result;
  bool get error => _result is Error;
  bool get completed => _result is Ok;
  Result<T>? get result => _result;

  void clearResult() { _result = null; notifyListeners(); }

  Future<void> _execute(CommandAction0<T> action) async {
    if (_running) return;                 // 防止重複觸發（例如按鈕連點）
    _running = true; _result = null; notifyListeners();
    try {
      _result = await action();
    } finally {
      _running = false; notifyListeners();
    }
  }
}

final class Command0<T> extends Command<T> {
  Command0(this._action);
  final CommandAction0<T> _action;
  Future<void> execute() async => _execute(_action);
}
```

- 暴露的狀態：`running`（進行中）、`error`（最近一次是 `Error`）、`completed`（最近一次是
  `Ok`）、`result`（原始 `Result`）、`clearResult()`（UI 消費完一次性事件，例如彈完 SnackBar 後
  呼叫，避免同一個錯誤重複觸發）。
- `_execute` 不 `catch` action 丟出的例外：action 被要求「不丟例外，一律回傳
  `Result.error`」；若真的丟出未捕捉的例外，`finally` 仍會重置 `running`，但例外會繼續往上
  傳——即 `Command` 本身**不是**全域例外守門員，錯誤分類與捕捉的責任還是在 service／repository
  層產生 `Result` 的地方。
- UI 用 `ListenableBuilder` 監聽 `Command` 本身（而不是整個 view model）來畫 loading／錯誤狀態；
  一次性動作（SnackBar、導頁）則在 `initState`／`dispose` 手動 `addListener`，處理完呼叫
  `clearResult()`。

官方文件也提到 pub.dev 上的 `command_it` 套件作為現成實作可替代手寫版。

**觀察（推測）**：官方文件本身有兩處不一致，值得在 FMP 設計時避開同樣的坑：
1. `result` 的 dartdoc 註解寫「回傳 `null` 表示 action 正在跑或以錯誤完成」，但實際程式碼裡
   `Error` 完成時 `_result` 不是 `null`，只有「進行中」或「已被 `clearResult()` 清除」才是
   `null`——註解與行為對不上。
2. Command 頁的 UI 範例混用了兩版 `Command`（簡化教學版 `error` 型別是 `Exception?`、重置方法叫
   `clear()`；完整版 `error` 是 `bool`、重置方法叫 `clearResult()`），照抄範例會編譯不過。

**對 FMP 的啟示**：`Result`/`Command` 這套官方模式本身**不含錯誤分類**——它解決的是「錯誤有沒有
被強制處理」，而不是「這個錯誤屬於網路／限流／需登入的哪一種」。分類（第 3 節）要另外設計一個
`sealed` 的錯誤型別，放進 `Result.error` 的位置或包成 `Exception` 傳遞。

## 2. Riverpod 錯誤處理與 Riverpod 3 自動重試

來源：<https://riverpod.dev/docs/from_provider/motivation>、
<https://riverpod.dev/docs/how_to/pull_to_refresh>、<https://riverpod.dev/docs/3.0_migration>、
<https://riverpod.dev/docs/whats_new>、
<https://github.com/rrousselgit/riverpod/blob/master/website/docs/concepts2/retry.mdx>
（經 context7 `/rrousselgit/riverpod`、`/websites/riverpod_dev` 取得，皆為官方倉庫／官方站台）。

### 2.1 `AsyncValue`、pattern matching、`ref.listen`

- `AsyncValue` 三態不變：loading／data／error，`ref.watch` 拿到後可用 Dart 3 pattern matching
  窮舉處理：

  ```dart
  switch (activity) {
    AsyncValue<Activity>(:final value?) => Text(value.activity),
    AsyncValue(:final error?) => Text('Error: $error'),
    _ => const CircularProgressIndicator(),
  }
  ```

- **一次性提示（SnackBar／導頁）用 `ref.listen`，不要把錯誤畫進 rebuild 出來的 UI**：官方範例
  直接在 `build()` 內呼叫 `ref.listen`，於 callback 裡跳 SnackBar；這與 FMP 的 `Command` 模式
  中「UI 監聽 `Command`、錯誤消費後 `clearResult()`」是同一個原則的兩種實作路徑（Riverpod 原生
  用 `ref.listen`，Command 模式用 `ChangeNotifier` 監聽）。
- `AsyncValue.guard` 用來把一段可能丟例外的非同步程式碼包成 `AsyncValue`（等同 `Result` 模式在
  Riverpod 世界的對應物）；具體 API 簽名建議實作前另查 `AsyncValue.guard` 的最新 dartdoc（本次
  未取得逐字原始碼，標**查不到逐字定義**，但其用途——取代手寫 `try { state = AsyncData(...) }
  catch (e, s) { state = AsyncError(e, s) }`——在官方遷移指南與多篇範例中反覆出現，可視為確認的
  用法慣例）。
- **重試（使用者手動或程式觸發）用 `ref.invalidate` / `ref.refresh`**：兩者關係官方原文——
  `ref.refresh` 是 `invalidate` 後接 `read` 的語法糖；只想丟棄快取用 `invalidate`，需要立刻拿到
  新值用 `refresh`。下拉重整範例：`onRefresh: () => ref.refresh(activityProvider.future)`。

### 2.2 Riverpod 3 自動重試機制（本次研究明確要求確認的部分）

**確認的事實**（來自
<https://github.com/rrousselgit/riverpod/blob/master/website/docs/concepts2/retry.mdx> 與
`whats_new.mdx`，非第三方轉述）：

- **是的，Riverpod 3.0 起，provider 初始化時丟出例外會自動重試，預設開啟、不需要額外設定。**
- **預設策略**：最多重試 **10 次**，退避時間呈指數成長，**從 200ms 到 6.4 秒**封頂
  （`whats_new.mdx` 原文：「starting with a 200ms delay that doubles with each retry, up to a
  maximum of 6.4 seconds」；`retry.mdx` 原文：「a provider can be retried up to 10 times, with
  an exponential backoff going from 200ms to 6.4 seconds」）。
- **兩種例外類型永遠不重試**：
  1. Dart 的 `Error`（例如 `StateError`、`ArgumentError`、`TypeError`）——官方理由：這類代表
     **程式本身有 bug、不可恢復**，重試沒有意義，只會在 log 裡製造噪音。
  2. `ProviderException`——當一個 provider 依賴的上游 provider 失敗時，這個 provider **自己不是
     失敗的源頭**，收到的是包著上游錯誤的 `ProviderException`；重試這個下游 provider 沒有用，
     真正該重試的是上游那個 provider。**推論**：若上游被設成不重試（`retry: (_, __) => null`），
     所有依賴它的下游也不會重試，因為它們收到的都是同一個 `ProviderException`。
- **自訂／關閉方式**（三個層級，任一層都用同一種函式簽名 `Duration? Function(int retryCount,
  Object error)`，回傳 `null` 表示停止重試）：
  - **全域關閉／自訂**：`ProviderScope(retry: (retryCount, error) => null, ...)`（App 根部）或
    `ProviderContainer(retry: ...)`（測試／無 widget 情境）。
  - **單一 provider 自訂**：程式碼產生語法 `@Riverpod(retry: myRetry)`；手動語法
    `NotifierProvider(TodoList.new, retry: myRetry)`。
  - **自訂函式範例**（官方原文）：
    ```dart
    Duration? myRetry(int retryCount, Object error) {
      if (retryCount >= 5) return null;
      if (error is ProviderException) return null;
      return Duration(milliseconds: 200 * (1 << retryCount));
    }
    ```

**對 FMP 的影響（分析，非官方原文，標為推測／設計建議）**：

- 這個機制作用在「provider **初始化**（`build()`）丟例外」的層級，跟 ADR 0012 講的「dio
  攔截器裡的限流與退避」是**兩層不同的重試**：Riverpod 3 的重試是「provider 建立失敗後重新跑一次
  `build()`」，會重新觸發底下所有的網路呼叫；dio 攔截器的重試是「單一 HTTP 請求失敗後在同一次
  `build()` 內重送」。兩者疊加時要小心**重試次數相乘**（例如 dio 層重試 3 次都失敗、丟出例外，
  Riverpod 又對這個 provider 重試 10 次，等於使用者體感一次操作背後打了 30 次請求）。
- 由於 Riverpod 3 預設對「所有非 `Error`／`ProviderException` 的例外」都重試，若 FMP 的統一錯誤
  型別（第 3 節）是一個 `sealed class`（例如 `SourceError`）而不是 Dart `Error`，它會被 Riverpod
  判定為「可重試」而自動重試 10 次——**除非** FMP 明確在該類 provider 上關閉或客製 `retry:`，依
  統一錯誤型別裡的 `retryable` 欄位（見第 3 節）動態決定要不要讓 Riverpod 繼續重試，或乾脆全域
  關閉 Riverpod 的自動重試、把「要不要重試」的決策權完全交給 ADR 0012 講的「音源宣告策略」那一層
  （dio 攔截器），避免兩層重試各自決策、互相打架。**這是需要擁有者決定的分工問題**，見本任務最終
  回報。
- `ref.invalidate` 觸發的「使用者按重試按鈕」跟 Riverpod 3 的自動重試是分開的兩件事：使用者手動
  重試沒有次數上限、也不受 `retry:` 參數控制。

## 3. Dart `sealed class` 慣例與錯誤欄位設計

### 3.1 `sealed` 語意（來源：<https://dart.dev/language/class-modifiers#sealed>，官方文件）

- `sealed` 建立一個「已知、可窮舉的子型別集合」；子型別必須跟 `sealed` 類別在**同一個
  library**。`sealed` 隱含 `abstract`（不能直接建構實例，但可以有 factory constructor、可以定義
  給子類別用的建構子）。
- **窮舉檢查的範圍是「直接子型別」**：編譯器只保證知道所有「直接」繼承／實作它的型別（因為都在
  同一個檔案／library），`switch` 若沒有涵蓋某個直接子型別會是編譯期錯誤。
- 子類別本身**不會**自動變成 `abstract` 或受限——除非額外標 `base`／`final`／`sealed`。官方文件
  另外指出：任何繼承或實作 `base`／`final` 類別的型別，自己也必須標 `base`、`final` 或
  `sealed`，但這條規則是為了保護「不能在外部繼續擴充」的保證，不是直接針對 `switch` 窮舉本身
  （這點官方頁面沒有明講兩者的因果關係，屬於**推測**：混用時若某個直接子型別本身是普通
  `class`，它可以在別的 library 被繼續擴充，但因為 `switch` 是依「型別比對」而非「集合相等」，
  對它的 `case` 依然會吃到它所有的子型別，因此不影響最外層 `switch` 的窮舉性——只影響「該子型別
  底下還能不能長出新分支、新分支會不會被外層 switch 的既有 case 隱性吃掉」）。
- 若不需要窮舉、或希望之後能新增子型別而不算破壞性 API 變更，官方建議改用 `final` 而非
  `sealed`。

**對 FMP 的啟示**：統一錯誤型別的頂層（例如 `SourceError`）應整個宣告在單一檔案／library 內、標
`sealed`，讓「網路、限流、需登入／憑證過期、風控驗證、地區／版權限制、找不到、解析失敗、不支援」
這八個分類都是它的直接子型別，`switch` 才能真正窮舉這八種、逼所有消費端（UI、log、重試邏輯）在
新增第九種分類時編譯期出錯而不是漏處理。

### 3.2 錯誤型別欄位設計的既有先例：NewPipe `ErrorInfo`

來源：
<https://github.com/TeamNewPipe/NewPipe/blob/dev/app/src/main/java/org/schabi/newpipe/error/ErrorInfo.kt>
（直接讀取官方倉庫原始碼確認，非轉述）。NewPipe（Android／Kotlin）用一個 `ErrorInfo`
（`Parcelable` data class）統一封裝所有要回報／顯示的錯誤，欄位：

| 欄位 | 型別 | 用途 |
|---|---|---|
| `stackTraces` | `Array<String>` | 原始例外的 stack trace（純文字化，供回報／log） |
| `userAction` | `UserAction`（enum） | **使用者當時在做什麼**（見 3.3），不是錯誤種類本身 |
| `request` | `String` | 觸發錯誤的請求描述（例如 URL） |
| `serviceId` | `String` | 是哪個服務／來源（YouTube、SoundCloud……）——對應 FMP 的**音源 id** |
| `message` | `ErrorMessage`（string 資源 id ＋格式參數） | **使用者看到的訊息 key**，不是寫死字串，走 i18n |
| `isReportable` | `Boolean` | 是否該讓使用者回報成 bug（區分「已知的來源錯誤」與「未預期的例外」） |
| `isRetryable` | `Boolean` | **可否重試**——對應 FMP 要的 retryable flag |
| `recaptchaUrl` | `String?` | 若是風控驗證碼，附上驗證頁 URL |
| `openInBrowserUrl` | `String?` | 提供「用瀏覽器打開」作為降級手段的連結 |

`ErrorInfo` 另有 `getMessage(context)` 方法把 `ErrorMessage`（string 資源 id + 格式參數）解析成
在地化字串——即「訊息不是存字串本身，而是存 key + 參數」，這正是研究要求的「user-facing message
key」模式的直接先例。

### 3.3 `UserAction`：值得借鏡但不是「錯誤分類」

來源：
<https://github.com/TeamNewPipe/NewPipe/blob/dev/app/src/main/java/org/schabi/newpipe/error/UserAction.kt>
（直接讀取確認，共 31 個列舉值，節錄）：

```kotlin
enum class UserAction(val message: String) {
    USER_REPORT("user report"),
    UI_ERROR("ui error"),
    SEARCHED("searched"),
    REQUESTED_STREAM("requested stream"),
    REQUESTED_CHANNEL("requested channel"),
    REQUESTED_PLAYLIST("requested playlist"),
    REQUESTED_COMMENTS("requested comments"),
    PLAY_STREAM("play stream"),
    DOWNLOAD_FAILED("download failed"),
    SUBSCRIPTION_UPDATE("subscription update"),
    // ……共 31 項
}
```

**重點澄清**：`UserAction` 記錄的是「使用者當下的操作情境」（搜尋、播放、訂閱更新……），**不是**
錯誤本身的分類（網路／限流／風控……）——那個分類在 NewPipe 裡是靠**例外的 Java／Kotlin 類別本身**
表達（見 3.4），`ErrorInfo` 只是把「操作情境」跟「例外物件」打包在一起，方便回報與 log 時同時看到
「使用者在幹嘛」與「發生了什麼」。**對 FMP 的啟示**：FMP 的統一錯誤型別要處理的是後者（例外分類本
身），至於「使用者當下在做什麼操作」這種情境資訊，可以是統一錯誤型別之外、由呼叫端（UI／
Command）附加的另一組 metadata，不必塞進 `sealed class` 的分支設計裡，否則分類會爆炸成「網路
×操作」的笛卡兒積。

### 3.4 NewPipe 用「例外類別階層」做分類，而非「一個大 enum」

來源：<https://github.com/TeamNewPipe/NewPipeExtractor> 的
`extractor/src/main/java/org/schabi/newpipe/extractor/exceptions/`（直接列出並讀取確認）：

```
ExtractionException                              （基底）
├─ ParsingException
│  ├─ ContentNotAvailableException
│  │  ├─ AgeRestrictedContentException           （年齡限制）
│  │  ├─ GeographicRestrictionException          （地區限制）
│  │  ├─ AccountTerminatedException              （帳號被終止，另帶 Reason.UNKNOWN/VIOLATION）
│  │  ├─ PrivateContentException
│  │  ├─ PaidContentException
│  │  ├─ SoundCloudGoPlusContentException
│  │  └─ YoutubeMusicPremiumContentException     （皆為「需要付費／VIP」的細分） 
│  └─ SignInConfirmNotBotException               （YouTube「確認你不是機器人」，見研究二）
├─ ContentNotSupportedException                  （不支援）
├─ UnsupportedTabException
└─ ReCaptchaException（帶 url 欄位）              （風控驗證碼，見研究二）
```

這與 Dart 的 `sealed class` 階層設計精神一致：用**型別本身**表達分類與繼承關係（`is
GeographicRestrictionException` 同時滿足「是地區限制」也「是內容不可用」的雙重身分），而不是
單一 enum 欄位——這點呼應擁有者要求的八分類其實有天然的包含關係（例如「地區限制」與「找不到」在
NewPipe 裡就是「內容不可用」的兩個具體子分類）。**建議（推測／設計方向）**：FMP 的 `sealed class`
分類可以參考這個層次，讓「找不到」與「地區／版權限制」共享一個中介型別，而不是八個平行、互不相干
的分支。

### 3.5 FMP 統一錯誤型別建議欄位（綜合本節先例，非官方規範）

依 ADR 0011（結構化錯誤欄位、log 需要音源與網路紀錄關聯）、ADR 0012（每音源宣告限流退避策略、
每音源列出「憑證無效」判定表）與本節先例，錯誤型別至少要能表達：

| 欄位 | 對應先例 | 用途 |
|---|---|---|
| 分類（`sealed` 的哪個子型別） | NewPipeExtractor 例外階層 | 網路／限流／需登入／風控／地區／找不到／解析失敗／不支援 |
| 音源 id | `ErrorInfo.serviceId` | ADR 0011 要求 log 帶音源；哪個 dio client 出的錯 |
| `retryable` flag | `ErrorInfo.isRetryable` | 決定要不要進退避重試（見研究二） |
| retry-after 等待時間 | 本研究項目 4 要求 | 來自 HTTP `Retry-After` 或音源自訂節流回應 |
| 使用者訊息 key（非寫死字串） | `ErrorInfo.message`（string 資源 id + 參數） | i18n；FMP 用 slang，key 對應 arb/slang 條目 |
| 原始 error + stackTrace | `ErrorInfo.stackTraces`；Flutter `Result.error` 帶 `Exception` | ADR 0011 錯誤歷史／log 門面要求的欄位 |
| 是否可回報／是否為預期錯誤 | `ErrorInfo.isReportable`；yt-dlp 的 `expected=True/False`（見研究二） | 區分「已知的來源行為」與「真的是 bug，需要診斷包／回報」 |

## 參考連結彙整

- Flutter：<https://docs.flutter.dev/app-architecture/design-patterns/result>、
  <https://docs.flutter.dev/app-architecture/design-patterns/command>
- Dart：<https://dart.dev/language/class-modifiers#sealed>
- Riverpod：<https://riverpod.dev/docs/from_provider/motivation>、
  <https://riverpod.dev/docs/how_to/pull_to_refresh>、
  <https://riverpod.dev/docs/3.0_migration>、<https://riverpod.dev/docs/whats_new>、
  <https://github.com/rrousselgit/riverpod/blob/master/website/docs/concepts2/retry.mdx>
- NewPipe：
  <https://github.com/TeamNewPipe/NewPipe/blob/dev/app/src/main/java/org/schabi/newpipe/error/ErrorInfo.kt>、
  <https://github.com/TeamNewPipe/NewPipe/blob/dev/app/src/main/java/org/schabi/newpipe/error/UserAction.kt>
- NewPipeExtractor：
  <https://github.com/TeamNewPipe/NewPipeExtractor/tree/dev/extractor/src/main/java/org/schabi/newpipe/extractor/exceptions>
