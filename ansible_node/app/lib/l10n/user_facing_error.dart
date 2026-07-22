import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../config/protocol.dart';
import '../services/atproto_client.dart';
import '../services/forum_host_client.dart';
import '../services/messenger_relay_client.dart';
import '../services/posting_gate.dart';
import '../services/relay_anchor_client.dart';
import '../services/relay_identity_client.dart';
import '../services/relay_ops_client.dart';
import 'app_l10n.dart';

/// Maps low-level exceptions to short, localized copy that is safe to show
/// directly in UI surfaces (snackbars, error panes).
///
/// Falls back to a generic message with a trimmed one-line detail so the user
/// never sees a bare `Exception: ...` stack string.
String userFacingError(BuildContext context, Object error) {
  if (_isUpgradeRequired(error)) {
    return context.uiCopy(
      zh: '請更新 App 以繼續同步。',
      en: 'Update the app to keep syncing.',
    );
  }
  if (error is ForumHostException && error.error == 'rate_limited') {
    return context.uiCopy(
      zh: '操作太頻繁，請稍後再試。',
      en: 'Too many requests; please try again later.',
    );
  }
  if (error is ForumHostException && error.error == 'not_board_creator') {
    return context.uiCopy(
      zh: '只有看板建立者可以編輯這個看板。',
      en: 'Only the board creator can edit this board.',
    );
  }
  if (error is ForumHostException && error.error == 'thread_locked') {
    return context.uiCopy(
      zh: '這個討論串已被板務鎖定，無法新增回覆。',
      en: 'This thread has been locked by the moderators.',
    );
  }
  if (error is RelayAnchorException) {
    final mapped = _anchorErrorCopy(context, error);
    if (mapped != null) return mapped;
  }
  if (_isPostingRequiresTier(error)) {
    return context.uiCopy(
      zh: '此看板僅限通過真人驗證的成員發文。請先完成真人驗證（升級驗證），再試一次。',
      en:
          'Only verified humans can post in this board. Complete identity '
          'verification first, then try again.',
    );
  }
  if (error is SocketException || error is HttpException) {
    return context.uiCopy(
      zh: '無法連線到伺服器，請檢查網路或同步設定後再試一次。',
      en:
          'Could not reach the server. Check your network or sync settings '
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
      en:
          'The server returned an unexpected response. Please try again '
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

/// Whether [error] is a relay/appview protocol-version rejection (HTTP 426
/// `{"error": "upgrade_required"}`): this build is older than the server's
/// minimum supported protocol version and must be updated (Phase 0 — API
/// versioning).
bool _isUpgradeRequired(Object error) {
  const code = AnsibleProtocol.upgradeRequiredCode;
  return switch (error) {
    ForumHostException(:final statusCode, :final error) =>
      statusCode == 426 || error == code,
    AtProtoException(:final statusCode, :final error) =>
      statusCode == 426 || error == code,
    RelayOpsException(:final statusCode, :final error) =>
      statusCode == 426 || error == code,
    MessengerRelayException(:final statusCode, :final error) =>
      statusCode == 426 || error == code,
    RelayIdentityException(:final statusCode, :final error) =>
      statusCode == 426 || error == code,
    RelayAnchorException(:final statusCode, :final error) =>
      statusCode == 426 || error == code,
    _ => false,
  };
}

/// Friendly bilingual copy for relay identity-anchor failures (recovery design
/// Task 4 endpoints). Returns null for codes that should fall through to the
/// generic mapping. 426 upgrade-required is handled earlier.
String? _anchorErrorCopy(BuildContext context, RelayAnchorException error) {
  if (error.statusCode == 426 ||
      error.error == AnsibleProtocol.upgradeRequiredCode) {
    return null; // handled by _isUpgradeRequired
  }
  // 423 account_frozen — a veto froze the account; manual resolution needed.
  if (error.statusCode == 423 || error.error == 'account_frozen') {
    return context.uiCopy(
      zh: '帳號已凍結，需人工協助才能繼續復原。',
      en: 'This account is frozen and needs manual help to recover.',
    );
  }
  switch (error.error) {
    case 'invalid_signature':
    case 'invalid_attestation':
    case 'invalid_recovery_proof':
      return context.uiCopy(
        zh: '簽章驗證失敗，無法完成這次身分重新錨定。',
        en:
            'Signature verification failed; the re-anchor could not be '
            'completed.',
      );
    case 'conflict':
      return context.uiCopy(
        zh: '與目前的身分錨定狀態衝突，請重新整理後再試一次。',
        en:
            'This conflicts with the current anchor state. Refresh and try '
            'again.',
      );
    case 'chain_mismatch':
      return context.uiCopy(
        zh: '身分錨定鏈對不上，請重新整理後再試一次。',
        en: 'The anchor chain does not line up. Refresh and try again.',
      );
    case 'malformed_anchor':
    case 'malformed_veto':
    case 'unknown_reason':
      return context.uiCopy(
        zh: '送出的身分錨定資料格式不正確。',
        en: 'The submitted anchor data was not valid.',
      );
  }
  // 409 without a recognised code still reads as a conflict.
  if (error.statusCode == 409) {
    return context.uiCopy(
      zh: '與目前的身分錨定狀態衝突，請重新整理後再試一次。',
      en:
          'This conflicts with the current anchor state. Refresh and try '
          'again.',
    );
  }
  return null;
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
