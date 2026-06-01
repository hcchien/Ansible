import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

extension AppL10nContext on BuildContext {
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ??
      lookupAppLocalizations(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      );

  bool get usesChineseUi {
    final appLocalizations = Localizations.of<AppLocalizations>(
      this,
      AppLocalizations,
    );
    if (appLocalizations == null) return true;
    return Localizations.localeOf(this).languageCode == 'zh';
  }

  String uiCopy({required String zh, required String en}) {
    return usesChineseUi ? zh : en;
  }
}
