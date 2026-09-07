import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'canonical_identity_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks whether the user has created an encrypted identity-key backup
/// (recovery design D5-b) so the UI can show recovery readiness
/// (「資料已產生 / 已確認保存 / ⚠ 尚未設定」 — Constitution must-have: readiness is
/// user-visible).
///
/// IMPORTANT (Constitution item 2): we record only a *flag and timestamp* that
/// the user produced a backup. The encrypted blob itself is exported by the
/// user (text/QR) and is NOT stored here — the key only ever leaves the device
/// as the passphrase-encrypted blob, never silently. This is a presence flag,
/// not key storage.
///
/// TODO(Task 3, app/did): once multi-device enrollment lands, readiness will
/// also reflect enrolled-device count (「可復原：2 裝置 + 備份」). This slice
/// tracks the backup flag only.
abstract class RecoveryReadinessStore {
  Future<bool> hasBackup();
  Future<void> markBackupSaved({CanonicalIdentity? identity});
  Future<bool> hasSavedBackup();

  /// Records that a backup was created at [at] (defaults to now, UTC).
  Future<void> markBackupCreated({DateTime? at, CanonicalIdentity? identity});

  /// The UTC time the backup was last created, or null.
  Future<DateTime?> lastBackupAt();

  /// Clears the backup flag (Constitution exit element: user can delete the
  /// backup; the readiness indicator must reflect that).
  Future<void> clearBackup();

  /// The user skipped the at-creation backup offer. Backup is opt-in /
  /// skippable (Constitution must-have), so we remember the skip in order to
  /// re-prompt ("nag once") on a subsequent launch — but only once, so we never
  /// nag relentlessly.
  Future<void> markBackupSkipped();

  /// True when the user skipped the offer AND has not yet been re-prompted (so
  /// the app should nag once now). Returns false if a backup already exists.
  Future<bool> shouldNagForBackup();

  /// Records that the one-time nag has now been shown, so we don't nag again.
  Future<void> markNagShown();
}

class SharedPreferencesRecoveryReadinessStore
    implements RecoveryReadinessStore {
  const SharedPreferencesRecoveryReadinessStore({
    this.identityStore = const SecureCanonicalIdentityStore(),
  });
  final CanonicalIdentityStore identityStore;

  String _scope(CanonicalIdentity identity) => sha256.convert(utf8.encode(
    '${identity.did}\u0000${identity.signingAlgorithm}\u0000${identity.publicKeyHex}')).toString();

  Future<String?> _identityScope([CanonicalIdentity? expected]) async {
    final current = await identityStore.load();
    if (expected != null && (current == null || _scope(expected) != _scope(current))) {
      throw StateError('recovery_identity_changed');
    }
    return current == null ? null : _scope(current);
  }

  Future<String?> _scoped(String key) async {
    final scope = await _identityScope();
    return scope == null ? null : '$key.$scope';
  }

  @override
  Future<void> markBackupSaved({CanonicalIdentity? identity}) async {
    final scope = await _identityScope(identity);
    if (scope == null) { throw StateError('recovery_identity_unavailable'); }
    final prefs = await SharedPreferences.getInstance();
    final generated = prefs.getString('$backupCreatedAtKey.$scope');
    if (generated == null) { throw StateError('backup_not_generated'); }
    await prefs.setString('elix-recovery-backup-saved.$scope', generated);
  }

  @override
  Future<bool> hasSavedBackup() async {
    final scope = await _identityScope();
    if (scope == null) return false;
    final prefs = await SharedPreferences.getInstance();
    final generated = prefs.getString('$backupCreatedAtKey.$scope');
    return generated != null && prefs.getString('elix-recovery-backup-saved.$scope') == generated;
  }

  static const String backupCreatedAtKey = 'elix-recovery-backup-created-at';
  static const String backupSkippedKey = 'elix-recovery-backup-skipped';
  static const String nagShownKey = 'elix-recovery-backup-nag-shown';

  @override
  Future<bool> hasBackup() async {
    return (await lastBackupAt()) != null;
  }

  @override
  Future<void> markBackupCreated({DateTime? at, CanonicalIdentity? identity}) async {
    final prefs = await SharedPreferences.getInstance();
    final scope = await _identityScope(identity);
    if (scope == null) { throw StateError('recovery_identity_unavailable'); }
    final key = '$backupCreatedAtKey.$scope';
    await prefs.remove('elix-recovery-backup-saved.$scope');
    await prefs.setString(
      key,
      (at ?? DateTime.now().toUtc()).toUtc().toIso8601String(),
    );
  }

  @override
  Future<DateTime?> lastBackupAt() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _scoped(backupCreatedAtKey);
    final raw = key == null ? null : prefs.getString(key);
    if (raw == null) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  @override
  Future<void> clearBackup() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _scoped(backupCreatedAtKey);
    final saved = await _scoped('elix-recovery-backup-saved');
    if (key != null) await prefs.remove(key);
    if (saved != null) await prefs.remove(saved);
  }

  @override
  Future<void> markBackupSkipped() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _scoped(backupSkippedKey);
    if (key != null) await prefs.setBool(key, true);
  }

  @override
  Future<bool> shouldNagForBackup() async {
    if (await hasBackup()) return false;
    final prefs = await SharedPreferences.getInstance();
    final skipKey = await _scoped(backupSkippedKey);
    final nagKey = await _scoped(nagShownKey);
    final skipped = skipKey != null && prefs.getBool(skipKey) == true;
    final nagged = nagKey != null && prefs.getBool(nagKey) == true;
    return skipped && !nagged;
  }

  @override
  Future<void> markNagShown() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _scoped(nagShownKey);
    if (key != null) await prefs.setBool(key, true);
  }
}

class InMemoryRecoveryReadinessStore implements RecoveryReadinessStore {
  InMemoryRecoveryReadinessStore({DateTime? backupAt}) : _backupAt = backupAt;

  DateTime? _backupAt;
  bool _saved = false;
  @override
  Future<void> markBackupSaved({CanonicalIdentity? identity}) async {
    if (_backupAt == null) throw StateError('backup_not_generated');
    _saved = true;
  }

  @override
  Future<bool> hasSavedBackup() async => _saved;
  bool _skipped = false;
  bool _nagShown = false;

  @override
  Future<bool> hasBackup() async => _backupAt != null;

  @override
  Future<void> markBackupCreated({DateTime? at, CanonicalIdentity? identity}) async {
    _saved = false;
    _backupAt = (at ?? DateTime.now().toUtc()).toUtc();
  }

  @override
  Future<DateTime?> lastBackupAt() async => _backupAt;

  @override
  Future<void> clearBackup() async {
    _saved = false;
    _backupAt = null;
  }

  @override
  Future<void> markBackupSkipped() async {
    _skipped = true;
  }

  @override
  Future<bool> shouldNagForBackup() async {
    if (await hasBackup()) return false;
    return _skipped && !_nagShown;
  }

  @override
  Future<void> markNagShown() async {
    _nagShown = true;
  }
}
