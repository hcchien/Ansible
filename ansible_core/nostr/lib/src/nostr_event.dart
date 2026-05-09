import 'dart:convert';

import 'package:crypto/crypto.dart';

class NostrEventDraft {
  final String pubkey;
  final int createdAt;
  final int kind;
  final List<List<String>> tags;
  final String content;

  const NostrEventDraft({
    required this.pubkey,
    required this.createdAt,
    required this.kind,
    required this.tags,
    required this.content,
  });

  String get serializedForId {
    return jsonEncode([0, pubkey, createdAt, kind, tags, content]);
  }

  String computeId() {
    return sha256.convert(utf8.encode(serializedForId)).toString();
  }
}

class NostrEvent {
  final String id;
  final String pubkey;
  final int createdAt;
  final int kind;
  final List<List<String>> tags;
  final String content;
  final String sig;

  const NostrEvent({
    required this.id,
    required this.pubkey,
    required this.createdAt,
    required this.kind,
    required this.tags,
    required this.content,
    required this.sig,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'pubkey': pubkey,
      'created_at': createdAt,
      'kind': kind,
      'tags': tags,
      'content': content,
      'sig': sig,
    };
  }

  factory NostrEvent.fromJson(Map<String, dynamic> json) {
    return NostrEvent(
      id: json['id'] as String,
      pubkey: json['pubkey'] as String,
      createdAt: json['created_at'] as int,
      kind: json['kind'] as int,
      tags: (json['tags'] as List<dynamic>)
          .map(
            (tag) => (tag as List<dynamic>)
                .map((value) => value.toString())
                .toList(),
          )
          .toList(),
      content: json['content'] as String,
      sig: json['sig'] as String,
    );
  }
}
