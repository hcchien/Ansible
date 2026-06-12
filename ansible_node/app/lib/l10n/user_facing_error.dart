import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'app_l10n.dart';

/// Maps low-level exceptions to short, localized copy that is safe to show
/// directly in UI surfaces (snackbars, error panes).
///
/// Falls back to a generic message with a trimmed one-line detail so the user
/// never sees a bare `Exception: ...` stack string.
String userFacingError(BuildContext context, Object error) {
  if (error is SocketException || error is HttpException) {
    return context.uiCopy(
      zh: '無法連線到伺服器，請檢查網路或同步設定後再試一次。',
      en: 'Could not reach the server. Check your network or sync settings '
          'and try again.',
    );
  }
  if (error is TimeoutException) {
    return context.uiCopy(
      zh: '連線逾時，請稍後再試。',
      en: 'The connection timed out. Please try again later.',
    );
  }
  if (error is FormatException) {
    return context.uiCopy(
      zh: '伺服器回應格式不正確，請稍後再試。',
      en: 'The server returned an unexpected response. Please try again '
          'later.',
    );
  }
  final detail = _shortDetail(error);
  final generic = context.uiCopy(
    zh: '發生未預期的錯誤，請再試一次。',
    en: 'Something went wrong. Please try again.',
  );
  return detail.isEmpty ? generic : '$generic\n($detail)';
}

String _shortDetail(Object error) {
  var text = error.toString().trim();
  const prefixes = ['Exception: ', 'Bad state: ', 'Invalid argument(s): '];
  for (final prefix in prefixes) {
    if (text.startsWith(prefix)) {
      text = text.substring(prefix.length).trim();
      break;
    }
  }
  final newline = text.indexOf('\n');
  if (newline != -1) text = text.substring(0, newline).trim();
  if (text.length > 120) text = '${text.substring(0, 117)}...';
  return text;
}
