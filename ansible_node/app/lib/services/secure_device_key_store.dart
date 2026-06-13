import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Platform-secure-storage backed [DeviceKeyStore] (recovery design Task 3).
///
/// Constitution must-have: the device PRIVATE key lives ONLY here and is NEVER
/// included in any backup. It is stored under dedicated keys, separate from the
/// identity key (`ansible_did_private_key`) the backup flow exports.
class SecureDeviceKeyStore implements DeviceKeyStore {
  final FlutterSecureStorage _storage;

  const SecureDeviceKeyStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  /// Dedicated secure-storage keys. These are intentionally distinct from the
  /// identity key so the device key is never swept into an identity backup.
  static const String deviceIdKey = 'ansible_device_id';
  static const String devicePublicKeyKey = 'ansible_device_public_key';
  static const String devicePrivateKeyKey = 'ansible_device_private_key';

  @override
  Future<DeviceKey?> load() async {
    final deviceId = await _storage.read(key: deviceIdKey);
    final publicKeyHex = await _storage.read(key: devicePublicKeyKey);
    final privateKeyHex = await _storage.read(key: devicePrivateKeyKey);
    if (deviceId == null || publicKeyHex == null || privateKeyHex == null) {
      return null;
    }
    return DeviceKey.fromStored(
      deviceId: deviceId,
      publicKeyHex: publicKeyHex,
      privateKeyHex: privateKeyHex,
    );
  }

  @override
  Future<void> save(DeviceKey key) async {
    await _storage.write(key: deviceIdKey, value: key.deviceId);
    await _storage.write(key: devicePublicKeyKey, value: key.publicKeyHex);
    await _storage.write(key: devicePrivateKeyKey, value: key.privateKeyHex);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: deviceIdKey);
    await _storage.delete(key: devicePublicKeyKey);
    await _storage.delete(key: devicePrivateKeyKey);
  }
}
