/// 靜態規則共用的原始碼前處理。
///
/// 每條掃 `lib/` 的規則都得先把註解拿掉，否則一句解釋「不要這樣寫」的註解就會
/// 把規則自己弄紅 —— 而那句註解通常正是規則存在的原因。
library;

/// 去掉 `//` 與 `/* */` 註解，保留字串常量的內容。
///
/// 不能用單純的 `//[^\n]*` 取代：`'https://music.163.com'` 裡的 `//` 會被當成
/// 註解開頭，把後面半行連同它的斷言目標一起吃掉。這裡沿著字串常量走，
/// 認得 `r''`、`'''`、`"""` 與跳脫字元。
String stripDartComments(String source) {
  final out = StringBuffer();
  var i = 0;

  while (i < source.length) {
    final ch = source[i];

    // 註解。
    if (ch == '/' && i + 1 < source.length) {
      final next = source[i + 1];
      if (next == '/') {
        while (i < source.length && source[i] != '\n') {
          i++;
        }
        continue;
      }
      if (next == '*') {
        final end = source.indexOf('*/', i + 2);
        i = end == -1 ? source.length : end + 2;
        continue;
      }
    }

    // 字串常量：原樣抄出來。
    if (ch == "'" ||
        ch == '"' ||
        (ch == 'r' && _opensStringAt(source, i + 1))) {
      final raw = ch == 'r';
      final quoteStart = raw ? i + 1 : i;
      final quote = source[quoteStart];
      final triple = source.startsWith(quote * 3, quoteStart);
      final closer = triple ? quote * 3 : quote;

      var j = quoteStart + closer.length;
      while (j < source.length) {
        if (!raw && source[j] == r'\') {
          j += 2;
          continue;
        }
        if (source.startsWith(closer, j)) {
          j += closer.length;
          break;
        }
        // 未閉合的單行字串不吃掉整個檔案。
        if (!triple && source[j] == '\n') break;
        j++;
      }

      out.write(source.substring(i, j));
      i = j;
      continue;
    }

    out.write(ch);
    i++;
  }

  return out.toString();
}

bool _opensStringAt(String source, int index) =>
    index < source.length && (source[index] == "'" || source[index] == '"');
