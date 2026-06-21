// Seeds a second user ("B") directly against a relay so follow/timeline can be
// tested without a second device/TestFlight. Reuses the exact wire contracts of
// the app:
//   - identity:  did:elix = deriveDidElix(pubKeyHex, handle)   (ansible_store)
//   - register:  POST /api/v2/identity/register {public_key_hex, handle_suffix}
//   - anchor:    POST /api/v2/identity/anchor   {did, public_key_hex, handle,
//                                                 registration_sig, nonce}
//                registration_sig = Ed25519(utf8(nonce))
//   - post op:   POST /api/v1/ops   {op_id, author_did, entity_type, entity_id,
//                                    op_type, payload, signature, schema_version}
//                signature = Ed25519(utf8(canonicalJson(signing-subset)))
// Crypto is standard Ed25519 (package:cryptography), interoperable with the
// relay's verifier. Header x-ansible-protocol:1 mirrors AnsibleProtocol.
//
// Usage:
//   dart run tool/seed_user_b.dart <handleSuffix> [boardId] [title]
//   dart run tool/seed_user_b.dart <handleSuffix> --seed=<64hex> [boardId] [title]
//
// Env: RELAY_BASE (default https://relay-dev.elix.cool)
//
// Prints the SEED hex — pass it back via --seed to reuse the same B identity.

import 'dart:convert';
import 'dart:io';

import 'package:ansible_store/ansible_store.dart';
import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

const _protocolHeader = {'x-ansible-protocol': '1'};

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

List<int> _unhex(String s) {
  final out = <int>[];
  for (var i = 0; i < s.length; i += 2) {
    out.add(int.parse(s.substring(i, i + 2), radix: 16));
  }
  return out;
}

/// Canonical JSON identical to the app's OpSignaturePayload: object keys sorted,
/// values JSON-encoded. The `payload` value is itself a JSON string.
String _canonicalJson(Object? value) {
  if (value is Map) {
    final entries = value.entries.toList()
      ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
    return '{${entries.map((e) => '${jsonEncode(e.key.toString())}:${_canonicalJson(e.value)}').join(',')}}';
  }
  if (value is List) return '[${value.map(_canonicalJson).join(',')}]';
  return jsonEncode(value);
}

Future<void> main(List<String> args) async {
  final relayBase = (Platform.environment['RELAY_BASE'] ??
          'https://relay-dev.elix.cool')
      .replaceAll(RegExp(r'/$'), '');
  final positional = <String>[];
  String? seedHex;
  String? murmurText;
  String? commentText;
  String? commentOn;
  for (final a in args) {
    if (a.startsWith('--seed=')) {
      seedHex = a.substring('--seed='.length).trim();
    } else if (a.startsWith('--murmur=')) {
      murmurText = a.substring('--murmur='.length);
    } else if (a.startsWith('--comment=')) {
      commentText = a.substring('--comment='.length);
    } else if (a.startsWith('--on=')) {
      commentOn = a.substring('--on='.length).trim();
    } else {
      positional.add(a);
    }
  }
  if (positional.isEmpty) {
    stderr.writeln(
      'usage: dart run tool/seed_user_b.dart <handleSuffix> [boardId] [title] [--seed=<64hex>]',
    );
    exit(64);
  }
  final suffix = positional[0];
  final boardId = positional.length > 1 ? positional[1] : null;
  final title = positional.length > 2 ? positional[2] : '哈囉，我是 $suffix';

  final algo = Ed25519();
  final SimpleKeyPair kp = seedHex != null && seedHex.isNotEmpty
      ? await algo.newKeyPairFromSeed(_unhex(seedHex))
      : await algo.newKeyPair();
  final pub = await kp.extractPublicKey();
  final pubHex = _hex(pub.bytes);
  final seed = await kp.extractPrivateKeyBytes();
  final handle = '$suffix.elix.cool';
  final did = deriveDidElix(identityKey: pubHex, handle: handle);

  Future<String> sign(String message) async {
    final sig = await algo.sign(utf8.encode(message), keyPair: kp);
    return _hex(sig.bytes);
  }

  stdout.writeln('relay   = $relayBase');
  stdout.writeln('handle  = $handle');
  stdout.writeln('did     = $did');
  stdout.writeln('pubKey  = $pubHex');
  stdout.writeln('SEED    = ${_hex(seed)}   (reuse with --seed=<this>)');
  stdout.writeln('');

  final client = http.Client();
  Future<http.Response> post(String path, Map<String, Object?> body) {
    return client.post(
      Uri.parse('$relayBase$path'),
      headers: {'content-type': 'application/json', ..._protocolHeader},
      body: jsonEncode(body),
    );
  }

  // 1) register -> nonce. Idempotent: a 409 handle_taken means B already
  // exists (re-run with the same --seed), so skip straight to publishing.
  stdout.writeln('→ register …');
  final reg = await post('/api/v2/identity/register', {
    'public_key_hex': pubHex,
    'handle_suffix': suffix,
  });
  if (reg.statusCode == 409) {
    stdout.writeln('  already registered (${reg.body.trim()}) — skipping anchor');
  } else if (reg.statusCode != 200) {
    stderr.writeln('register failed: ${reg.statusCode} ${reg.body}');
    exit(1);
  } else {
    final regBody = jsonDecode(reg.body) as Map<String, dynamic>;
    final nonce = regBody['nonce'] as String;
    stdout.writeln('  nonce = $nonce');

    // 2) anchor (registration_sig = Ed25519(utf8(nonce)))
    stdout.writeln('→ anchor …');
    final anc = await post('/api/v2/identity/anchor', {
      'did': did,
      'public_key_hex': pubHex,
      'handle': handle,
      'registration_sig': await sign(nonce),
      'nonce': nonce,
    });
    if (anc.statusCode != 200) {
      stderr.writeln('anchor failed: ${anc.statusCode} ${anc.body}');
      exit(1);
    }
    stdout.writeln('  anchored: ${anc.body}');
  }

  // 3) optional content. Signs the op (Ed25519 over canonical-JSON subset) and
  // POSTs to /api/v1/ops. A thread (boardId) lands in the board listing; a
  // murmur is feed-surfaceable for the Following timeline.
  Future<void> publishOp(OpsQueueEntry entry, String label) async {
    final signingMessage = _canonicalJson({
      'author_did': entry.authorDid,
      'entity_id': entry.entityId,
      'entity_type': entry.entityType,
      'op_id': entry.opId,
      'op_type': entry.opType,
      'payload': entry.payload,
    });
    final ops = await post('/api/v1/ops', {
      'op_id': entry.opId,
      'author_did': entry.authorDid,
      'entity_type': entry.entityType,
      'entity_id': entry.entityId,
      'op_type': entry.opType,
      'payload': entry.payload,
      'signature': await sign(signingMessage),
      'schema_version': entry.schemaVersion,
    });
    if (ops.statusCode != 202) {
      stderr.writeln('$label ingest failed: ${ops.statusCode} ${ops.body}');
      exit(1);
    }
    stdout.writeln('  $label published: ${ops.body}');
  }

  if (boardId == null && murmurText == null && commentText == null) {
    stdout.writeln(
      '\n✓ B registered. Add content, e.g.:'
      '\n  dart run tool/seed_user_b.dart $suffix <boardId> "$title" --seed=${_hex(seed)}'
      '\n  dart run tool/seed_user_b.dart $suffix --murmur="hello" --seed=${_hex(seed)}'
      '\n  dart run tool/seed_user_b.dart $suffix --comment="nice!" --on=<contentId> --seed=${_hex(seed)}',
    );
    client.close();
    return;
  }

  if (boardId != null) {
    stdout.writeln('→ publish thread to board $boardId …');
    await publishOp(
      CrdtOpBuilder.createThread(
        authorDid: did,
        entityId: const Uuid().v4(),
        boardId: boardId,
        title: title,
      ),
      'thread',
    );
  }
  if (murmurText != null) {
    stdout.writeln('→ publish murmur …');
    await publishOp(
      CrdtOpBuilder.createMurmur(
        authorDid: did,
        entityId: const Uuid().v4(),
        text: murmurText,
      ),
      'murmur',
    );
  }
  if (commentText != null) {
    if (commentOn == null || commentOn.isEmpty) {
      stderr.writeln('--comment requires --on=<contentId>');
      exit(64);
    }
    stdout.writeln('→ publish comment on $commentOn …');
    // A comment is a post op whose threadId is the target content's entity id
    // and whose board is empty (board-less content discussion).
    await publishOp(
      CrdtOpBuilder.createPost(
        authorDid: did,
        entityId: const Uuid().v4(),
        boardId: '',
        threadId: commentOn,
        content: commentText,
      ),
      'comment',
    );
  }
  stdout.writeln('\n✓ Done. B=$did');
  client.close();
}
