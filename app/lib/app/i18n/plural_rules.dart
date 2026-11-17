import 'package:fmp/app/i18n/strings.g.dart';

/// 中文沒有單複數：slang 內建的複數規則不含 zh，不設的話每次取字串都警告。
/// 所有形式都取 `other`。
void configurePluralRules() {
  LocaleSettings.setPluralResolverSync(
    language: 'zh',
    cardinalResolver: (n, {zero, one, two, few, many, other}) => other!,
  );
}
