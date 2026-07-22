import 'package:ansible_store/ansible_store.dart';

import 'oid4vci_wallet_client.dart';
import 'private_board_crypto_service.dart';
import 'wallet_holder_key_service.dart';

class PrivateBoardOpFactory {
  PrivateBoardOpFactory({
    PrivateBoardCryptoService? crypto,
    HardwareHolderJwtSigner? holder,
    Future<String> Function()? pairwiseSubject,
  }) : _crypto = crypto ?? PrivateBoardCryptoService(),
       _holder = holder,
       _pairwiseSubjectOverride = pairwiseSubject;

  final PrivateBoardCryptoService _crypto;
  final HardwareHolderJwtSigner? _holder;
  final Future<String> Function()? _pairwiseSubjectOverride;

  Future<String> _pairwiseSubject(String boardId) =>
      _pairwiseSubjectOverride?.call() ??
      (_holder ??
              HardwareHolderJwtSigner(
                key: BoardHolderKeyService(boardId: boardId),
              ))
          .pairwiseDid();

  Future<OpsQueueEntry> createThread({
    required HostedBoardProjection board,
    required String authorDid,
    required String entityId,
    required String title,
    String? description,
    required DateTime createdAt,
  }) async {
    _requireReady(board);
    final envelope = await _crypto.encryptContent(
      boardId: board.hostedBoardId,
      epoch: board.encryptionEpoch,
      policyVersion: board.accessPolicyVersion,
      recordId: entityId,
      recordType: 'thread',
      authorPairwiseId: await _pairwiseSubject(board.hostedBoardId),
      createdAt: createdAt,
      plaintext: {
        'title': title,
        if (description != null) 'description': description,
      },
    );
    return CrdtOpBuilder.createPrivateThread(
      authorDid: authorDid,
      entityId: entityId,
      boardId: board.hostedBoardId,
      privateEnvelope: envelope.toJson(),
    );
  }

  Future<OpsQueueEntry> createPost({
    required HostedBoardProjection board,
    required String authorDid,
    required String entityId,
    required String threadId,
    required String content,
    String? parentPostId,
    required DateTime createdAt,
  }) async {
    _requireReady(board);
    final envelope = await _crypto.encryptContent(
      boardId: board.hostedBoardId,
      epoch: board.encryptionEpoch,
      policyVersion: board.accessPolicyVersion,
      recordId: entityId,
      recordType: 'post',
      authorPairwiseId: await _pairwiseSubject(board.hostedBoardId),
      createdAt: createdAt,
      plaintext: {'content': content},
    );
    return CrdtOpBuilder.createPrivatePost(
      authorDid: authorDid,
      entityId: entityId,
      boardId: board.hostedBoardId,
      threadId: threadId,
      parentPostId: parentPostId,
      privateEnvelope: envelope.toJson(),
    );
  }

  void _requireReady(HostedBoardProjection board) {
    if (board.contentVisibility != 'end_to_end_encrypted' ||
        board.encryptionState != 'ready' ||
        board.encryptionEpoch < 1) {
      throw const PrivateBoardCryptoException('private_board_not_ready');
    }
  }
}
