enum MessengerMessageDirection {
  inbound,
  outbound;

  static MessengerMessageDirection parse(String value) {
    return MessengerMessageDirection.values.firstWhere(
      (item) => item.name == value,
      orElse: () {
        throw ArgumentError('Unknown MessengerMessageDirection "$value"');
      },
    );
  }
}

enum MessengerMessageStatus {
  pending,
  sent,
  received,
  decryptFailed,
  acked;

  static MessengerMessageStatus parse(String value) {
    return MessengerMessageStatus.values.firstWhere(
      (item) => item.name == value,
      orElse: () {
        throw ArgumentError('Unknown MessengerMessageStatus "$value"');
      },
    );
  }
}

class MessengerDeviceRecord {
  final String subjectDid;
  final String deviceId;
  final String identityKeyPublic;
  final String? identityKeyPrivateRef;
  final bool isLocal;
  final int? signedPreKeyId;
  final String? signedPreKeyPublic;
  final String? signedPreKeyPrivateRef;
  final String? signedPreKeySignature;
  final String? bindingJson;
  final String? bindingSignature;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const MessengerDeviceRecord({
    required this.subjectDid,
    required this.deviceId,
    required this.identityKeyPublic,
    this.identityKeyPrivateRef,
    this.isLocal = false,
    this.signedPreKeyId,
    this.signedPreKeyPublic,
    this.signedPreKeyPrivateRef,
    this.signedPreKeySignature,
    this.bindingJson,
    this.bindingSignature,
    required this.createdAt,
    this.updatedAt,
  });

  MessengerDeviceRecord copyWith({bool? isLocal}) {
    return MessengerDeviceRecord(
      subjectDid: subjectDid,
      deviceId: deviceId,
      identityKeyPublic: identityKeyPublic,
      identityKeyPrivateRef: identityKeyPrivateRef,
      isLocal: isLocal ?? this.isLocal,
      signedPreKeyId: signedPreKeyId,
      signedPreKeyPublic: signedPreKeyPublic,
      signedPreKeyPrivateRef: signedPreKeyPrivateRef,
      signedPreKeySignature: signedPreKeySignature,
      bindingJson: bindingJson,
      bindingSignature: bindingSignature,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

class MessengerPreKeyRecord {
  final String deviceId;
  final int preKeyId;
  final String publicKey;
  final String? privateKeyRef;
  final DateTime createdAt;
  final DateTime? publishedAt;
  final DateTime? consumedAt;

  const MessengerPreKeyRecord({
    required this.deviceId,
    required this.preKeyId,
    required this.publicKey,
    this.privateKeyRef,
    required this.createdAt,
    this.publishedAt,
    this.consumedAt,
  });
}

class MessengerSessionRecord {
  final String localDeviceId;
  final String remoteDid;
  final String remoteDeviceId;
  final String protocolVersion;
  final String sessionState;
  final DateTime updatedAt;

  const MessengerSessionRecord({
    required this.localDeviceId,
    required this.remoteDid,
    required this.remoteDeviceId,
    this.protocolVersion = 'signal-mvp-v1',
    required this.sessionState,
    required this.updatedAt,
  });
}

class MessengerConversationRecord {
  final String conversationId;
  final String peerDid;
  final String? title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastMessageAt;

  const MessengerConversationRecord({
    required this.conversationId,
    required this.peerDid,
    this.title,
    required this.createdAt,
    required this.updatedAt,
    this.lastMessageAt,
  });
}

class MessengerMessageRecord {
  final String messageId;
  final String conversationId;
  final MessengerMessageDirection direction;
  final MessengerMessageStatus status;
  final String? plaintext;
  final String? ciphertextType;
  final String? ciphertext;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const MessengerMessageRecord({
    required this.messageId,
    required this.conversationId,
    required this.direction,
    required this.status,
    this.plaintext,
    this.ciphertextType,
    this.ciphertext,
    required this.createdAt,
    this.updatedAt,
  });
}
