// Cold-start seeding (PM review P0): creates the GENESIS boards + opening
// threads on a relay so day-one visitors find a living forum, not a ghost
// town. Reuses the exact wire contracts of the app (same as seed_user_b):
//   - identity register/anchor  (POST /api/v2/identity/{register,anchor})
//   - board creation            (POST /api/v1/forum-host/boards, signed
//                                create_board intent, canonical JSON)
//   - thread ops                (POST /api/v1/ops, signed CRDT ops)
//
// The founding author is a real, reusable identity — pass --seed to keep
// publishing as the same founder across runs (idempotent: existing handle
// and existing board slugs are skipped, so re-running tops up missing
// pieces only).
//
// Usage:
//   dart run tool/seed_genesis.dart <founderHandleSuffix> [--seed=<64hex>]
//       [--boards=<path/to/genesis_boards.json>]
//
// Env: RELAY_BASE (default https://relay-dev.elix.cool)
//
// Board config JSON: [{"title": ..., "description": ...,
//   "min_post_tier": null|"verified_human", "opening_thread": ...}, ...]
// Without --boards, the built-in genesis set below is used (行銷策略書:
// 獲客主訴求「沒有網軍的真人討論區」 — the genesis boards make that promise
// visitable on day one).

import 'dart:convert';
import 'dart:io';

import 'package:ansible_store/ansible_store.dart';
import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

const _protocolHeader = {'x-ansible-protocol': '1'};

/// Built-in genesis set: broad, conversation-forward topics with a zh-Hant
/// voice, one 真人版 to showcase the flagship gate.
const _defaultBoards = [
  {
    'title': '大廳',
    'description': '新來的先坐。自我介紹、問題、還不知道往哪放的話題都歡迎。',
    'min_post_tier': null,
    'opening_thread': '歡迎來到 Elix — 說說你從哪裡來？',
  },
  {
    'title': '公共討論（真人版）',
    'description': '公共議題的長對話。這個板要求真人驗證才能發文 — 沒有機器人，沒有網軍。',
    'min_post_tier': 'verified_human',
    'opening_thread': '如果一個討論區保證每個發言的都是真人，你最想聊什麼？',
  },
  {
    'title': '工具與工作流',
    'description': '軟體、硬體、習慣。讓日子好過一點的東西。',
    'min_post_tier': null,
    'opening_thread': '今年真正改變你工作方式的一個工具',
  },
  {
    'title': '讀書會',
    'description': '正在讀什麼、讀完想聊什麼。長文歡迎。',
    'min_post_tier': null,
    'opening_thread': '最近讓你停下來想很久的一本書（或一篇文章）',
  },
];

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

List<int> _unhex(String s) {
  final out = <int>[];
  for (var i = 0; i < s.length; i += 2) {
    out.add(int.parse(s.substring(i, i + 2), radix: 16));
  }
  return out;
}

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
  String? boardsPath;
  for (final a in args) {
    if (a.startsWith('--seed=')) {
      seedHex = a.substring('--seed='.length).trim();
    } else if (a.startsWith('--boards=')) {
      boardsPath = a.substring('--boards='.length).trim();
    } else {
      positional.add(a);
    }
  }
  if (positional.isEmpty) {
    stderr.writeln(
      'usage: dart run tool/seed_genesis.dart <founderHandleSuffix> '
      '[--seed=<64hex>] [--boards=<json>]',
    );
    exit(64);
  }
  final suffix = positional[0];

  final boards = boardsPath == null
      ? _defaultBoards
      : (jsonDecode(File(boardsPath).readAsStringSync()) as List)
          .cast<Map<String, dynamic>>();

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
  stdout.writeln('founder = $handle ($did)');
  stdout.writeln('SEED    = ${_hex(seed)}   (KEEP THIS — reuse with --seed=)');
  stdout.writeln('');

  final client = http.Client();
  Future<http.Response> post(String path, Map<String, Object?> body) {
    return client.post(
      Uri.parse('$relayBase$path'),
      headers: {'content-type': 'application/json', ..._protocolHeader},
      body: jsonEncode(body),
    );
  }

  // 1) Founder identity (idempotent: 409 = already registered).
  final reg = await post('/api/v2/identity/register', {
    'public_key_hex': pubHex,
    'handle_suffix': suffix,
  });
  if (reg.statusCode == 409) {
    stdout.writeln('founder already registered — continuing');
  } else if (reg.statusCode != 200) {
    stderr.writeln('register failed: ${reg.statusCode} ${reg.body}');
    exit(1);
  } else {
    final nonce =
        (jsonDecode(reg.body) as Map<String, dynamic>)['nonce'] as String;
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
    stdout.writeln('founder anchored');
  }

  // Existing boards (idempotency: skip titles that already exist).
  final listing = await client.get(
    Uri.parse('$relayBase/api/v1/forum-host/boards'),
    headers: _protocolHeader,
  );
  final existingTitles = <String>{};
  if (listing.statusCode == 200) {
    for (final board
        in ((jsonDecode(listing.body) as Map)['boards'] as List? ?? [])) {
      final title = (board as Map)['title'];
      if (title is String) existingTitles.add(title);
    }
  }

  // 2) Boards + opening threads.
  const uuid = Uuid();
  for (final config in boards) {
    final title = config['title'] as String;
    if (existingTitles.contains(title)) {
      stdout.writeln('board "$title" exists — skipped');
      continue;
    }

    final intentId = uuid.v4();
    final createdAt = DateTime.now().toUtc();
    final expiresAt = createdAt.add(const Duration(minutes: 5));
    final minPostTier = config['min_post_tier'] as String?;
    final postingPolicy =
        minPostTier == null ? null : {'min_post_tier': minPostTier};

    // Same canonical intent payload the app signs (CreateHostedBoardIntent).
    final canonical = <String, Object?>{
      'action': 'create_board',
      'author_did': did,
      'board': {
        if ((config['description'] as String?)?.isNotEmpty ?? false)
          'description': config['description'],
        if (postingPolicy != null) 'posting_policy': postingPolicy,
        'title': title,
      },
      'created_at': createdAt.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
      'intent_id': intentId,
      'target_forum_host': relayBase,
      'type': 'io.trisaura.forum.createBoard',
      'version': 1,
    };

    final create = await post('/api/v1/forum-host/boards', {
      ...canonical,
      'signature': await sign(jsonEncode(canonical)),
    });
    if (create.statusCode != 201) {
      stderr.writeln(
        'create board "$title" failed: ${create.statusCode} ${create.body}',
      );
      exit(1);
    }
    final hostedBoardId =
        (jsonDecode(create.body) as Map)['hosted_board_id'] as String;
    stdout.writeln('board "$title" created ($hostedBoardId)');

    final openingThread = config['opening_thread'] as String?;
    if (openingThread != null && openingThread.isNotEmpty) {
      final entry = CrdtOpBuilder.createThread(
        authorDid: did,
        entityId: uuid.v4(),
        boardId: hostedBoardId,
        title: openingThread,
      );
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
        stderr.writeln(
          '  opening thread failed: ${ops.statusCode} ${ops.body}',
        );
      } else {
        stdout.writeln('  opening thread published');
      }
    }
  }

  stdout.writeln('\n✓ Genesis seeding done. Founder=$did');
  stdout.writeln(
    '  Next (runbook): recruit founding posters into each board and keep a '
    'posting cadence for the first weeks — see '
    'docs/operations/cold-start-seeding.md',
  );
  client.close();
}
