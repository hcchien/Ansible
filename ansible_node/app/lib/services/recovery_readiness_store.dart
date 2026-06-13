import 'package:shared_preferences/shared_preferences.dart';

/// Tracks whether the user has created an encrypted identity-key backup
/// (recovery design D5-b) so the UI can show recovery readiness
/// (「可復原：已備份 / ⚠ 尚未備份」 — Constitution must-have: readiness is
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

  /// Records that a backup was created at [at] (defaults to now, UTC).
  Future<void> markBackupCreated({DateTime? at});

  /// The UTC time the backup was last created, or null.
  Future<DateTime?> lastBackupAt();

  /// Clears the backup flag (Constitution exit element: user can delete the
  /// backup; the readiness indicator must reflect that).
  Future<void> clearBackup();
}

class SharedPreferencesRecoveryReadinessStore
    implements RecoveryReadinessStore {
  const SharedPreferencesRecoveryReadinessStore();

  static const String backupCreatedAtKey = 'elix-recovery-backup-created-at';

  @override
  Future<bool> hasBackup() async {
    return (await lastBackupAt()) != null;
  }

  @override
  Future<void> markBackupCreated({DateTime? at}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      backupCreatedAtKey,
      (at ?? DateTime.now().toUtc()).toUtc().toIso8601String(),
    );
  }

  @override
  Future<DateTime?> lastBackupAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(backupCreatedAtKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  @override
  Future<void> clearBackup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(backupCreatedAtKey);
  }
}

class InMemoryRecoveryReadinessStore implements RecoveryReadinessStore {
  InMemoryRecoveryReadinessStore({DateTime? backupAt}) : _backupAt = backupAt;

  DateTime? _backupAt;

  @override
  Future<bool> hasBackup() async => _backupAt != null;

  @override
  Future<void> markBackupCreated({DateTime? at}) async {
    _backupAt = (at ?? DateTime.now().toUtc()).toUtc();
  }

  @override
  Future<DateTime?> lastBackupAt() async => _backupAt;

  @override
  Future<void> clearBackup() async {
    _backupAt = null;
  }
}
