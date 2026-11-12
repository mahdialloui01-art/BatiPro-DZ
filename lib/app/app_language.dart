import 'package:flutter/foundation.dart';

/// Current BatiPro interface language. Persisted in AppStorage by settings.
class AppLanguage {
  AppLanguage._();

  static final ValueNotifier<String> current = ValueNotifier<String>('ar');

  static bool get isFrench => current.value == 'fr';

  static void set(String language) {
    current.value = language == 'fr' ? 'fr' : 'ar';
  }

  static String text(String arabic, String french) =>
      isFrench ? french : arabic;
}
