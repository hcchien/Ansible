import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../services/atproto_client.dart';
import '../services/forum_host_client.dart';
import '../services/posting_gate.dart';
import 'app_l10n.dart';

/// Maps low-level exceptions to short, localized copy that is safe to show
/// directly in UI surfaces (snackbars, error panes).
///
/// Falls back to a generic message with a trimmed one-line detail so the user
/// never sees a bare `Exception: ...` stack string.
String userFacingError(BuildContext context, Object error) {
  if (_isPostingRequiresTier(error)) {
    return context.uiCopy(
      zh: '此看板僅限通過真人驗證的成員發文。請先完成真人驗證（升級驗證），再試一次。',
      en: 'Only verified humans can post in this board. Complete identity '
          'verification first, then try again.',
    );
  }
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

/// Whether [error] is the relay's reason-coded posting-gate rejection
/// (HTTP 403 with `{"error": "posting_requires_tier", ...}`), regardless of
/// which client surfaced it.
bool _isPostingRequiresTier(Object error) {
  if (error is ForumHostException) {
    return error.error == PostingGate.requiresTierErrorCode ||
        error.body['error'] == PostingGate.requiresTierErrorCode;
  }
  if (error is AtProtoException) {
    return error.error == PostingGate.requiresTierErrorCode;
  }
  return false;
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
