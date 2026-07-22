import 'package:ansible_store/ansible_store.dart';

import 'board_access_presentation_service.dart';
import 'private_board_crypto_service.dart';
import 'private_board_key_client.dart';

class PrivateBoardRotationService {
  PrivateBoardRotationService({
    required this.access,
    PrivateBoardCryptoService? crypto,
  }) : _crypto = crypto ?? PrivateBoardCryptoService();

  final BoardAccessPresentationService access;
  final PrivateBoardCryptoService _crypto;

  Future<int> rotate({
    required Uri forumHost,
    required HostedBoardProjection board,
  }) async {
    if (board.contentVisibility != 'end_to_end_encrypted') {
      throw const PrivateBoardCryptoException('not_encrypted_board');
    }
    final capability = await access.authorize(
      forumHost: forumHost,
      boardId: board.hostedBoardId,
      action: 'moderate',
    );
    final client = PrivateBoardKeyClient(
      forumHost: forumHost,
      boardId: board.hostedBoardId,
      access: access,
    );
    final local = await _crypto.ensureDeviceKey(board.hostedBoardId);
    await client.registerDevice(
      capability: capability,
      publicKeyHex: local.publicKeyHex,
    );
    final devices = await client.listDevices(capability: capability);
    if (devices.isEmpty) {
      throw const PrivateBoardCryptoException('no_active_devices');
    }
    final epoch = board.encryptionEpoch + 1;
    await _crypto.createEpoch(board.hostedBoardId, epoch);
    final envelopes = <BoardEpochKeyEnvelope>[];
    for (final device in devices) {
      envelopes.add(
        await _crypto.wrapEpochKey(
          boardId: board.hostedBoardId,
          epoch: epoch,
          policyVersion: board.accessPolicyVersion,
          recipientDeviceKeyId: device.deviceKeyId,
          recipientPublicKeyHex: device.publicKeyHex,
        ),
      );
    }
    await client.activateEpoch(
      capability: capability,
      epoch: epoch,
      policyVersion: board.accessPolicyVersion,
      envelopes: envelopes,
    );
    return epoch;
  }
}
