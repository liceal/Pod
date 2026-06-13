import 'package:flutter/material.dart';

extension LocalizationExtension on BuildContext {
  bool get isChineseUi {
    final locale = Localizations.localeOf(this);
    return locale.languageCode != 'en';
  }

  String text(String zh, String en) {
    return isChineseUi ? zh : en;
  }
}
