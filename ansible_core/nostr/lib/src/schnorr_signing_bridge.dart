import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'nostr_event_signer.dart';

class SchnorrSigningBridge implements NostrSigningBridge {
  static final BigInt _p = BigInt.parse(
    'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F',
    radix: 16,
  );
  static final BigInt _n = BigInt.parse(
    'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141',
    radix: 16,
  );
  static final _Point _g = _Point(
    BigInt.parse(
      '79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798',
      radix: 16,
    ),
    BigInt.parse(
      '483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8',
      radix: 16,
    ),
  );

  final String? auxRandHex;

  const SchnorrSigningBridge({this.auxRandHex});

  @override
  Future<String> signEventId({
    required String privateKeyHex,
    required String eventIdHex,
  }) async {
    return sign(
      privateKeyHex: privateKeyHex,
      messageHex: eventIdHex,
      auxRandHex: auxRandHex,
    );
  }

  static String derivePublicKeyHex(String privateKeyHex) {
    final d0 = _normalizeScalar(privateKeyHex, label: 'private key');
    final point = _mul(d0, _g);
    if (point == null) throw ArgumentError('Invalid private key');
    return _bytesToHex(_bytes32(point.x));
  }

  static String sign({
    required String privateKeyHex,
    required String messageHex,
    String? auxRandHex,
  }) {
    final d0 = _normalizeScalar(privateKeyHex, label: 'private key');
    final message = _hexToBytes(messageHex, expectedLength: 32);
    final aux = auxRandHex == null
        ? Uint8List(32)
        : _hexToBytes(auxRandHex, expectedLength: 32);

    final p = _mul(d0, _g);
    if (p == null) throw ArgumentError('Invalid private key');
    final d = _hasEvenY(p) ? d0 : _n - d0;
    final px = _bytes32(p.x);

    final t = _xor(_bytes32(d), _taggedHash('BIP0340/aux', aux));
    final rand = _taggedHash(
      'BIP0340/nonce',
      Uint8List.fromList([...t, ...px, ...message]),
    );
    final k0 = _bytesToInt(rand) % _n;
    if (k0 == BigInt.zero) throw StateError('BIP-340 nonce is zero');

    final r = _mul(k0, _g);
    if (r == null) throw StateError('Invalid nonce point');
    final k = _hasEvenY(r) ? k0 : _n - k0;
    final rx = _bytes32(r.x);

    final e =
        _bytesToInt(
          _taggedHash(
            'BIP0340/challenge',
            Uint8List.fromList([...rx, ...px, ...message]),
          ),
        ) %
        _n;
    final sig = [...rx, ..._bytes32((k + e * d) % _n)];
    return _bytesToHex(sig);
  }

  static BigInt _normalizeScalar(String hex, {required String label}) {
    final bytes = _hexToBytes(hex, expectedLength: 32);
    final scalar = _bytesToInt(bytes);
    if (scalar <= BigInt.zero || scalar >= _n) {
      throw ArgumentError('Invalid $label scalar');
    }
    return scalar;
  }

  static Uint8List _taggedHash(String tag, Uint8List message) {
    final tagHash = sha256.convert(utf8.encode(tag)).bytes;
    return Uint8List.fromList(
      sha256.convert([...tagHash, ...tagHash, ...message]).bytes,
    );
  }

  static _Point? _mul(BigInt scalar, _Point point) {
    var n = scalar;
    _Point? result;
    var addend = point;

    while (n > BigInt.zero) {
      if (n.isOdd) result = _add(result, addend);
      addend = _add(addend, addend)!;
      n >>= 1;
    }
    return result;
  }

  static _Point? _add(_Point? a, _Point? b) {
    if (a == null) return b;
    if (b == null) return a;
    if (a.x == b.x && (a.y + b.y) % _p == BigInt.zero) return null;

    final lambda = a.x == b.x && a.y == b.y
        ? (BigInt.from(3) * a.x * a.x) * _modInverse(BigInt.two * a.y, _p)
        : (b.y - a.y) * _modInverse(b.x - a.x, _p);
    final x = _mod(lambda * lambda - a.x - b.x, _p);
    final y = _mod(lambda * (a.x - x) - a.y, _p);
    return _Point(x, y);
  }

  static BigInt _modInverse(BigInt value, BigInt modulus) {
    return _mod(value, modulus).modPow(modulus - BigInt.two, modulus);
  }

  static bool _hasEvenY(_Point point) => !point.y.isOdd;

  static BigInt _mod(BigInt value, BigInt modulus) {
    final result = value % modulus;
    return result >= BigInt.zero ? result : result + modulus;
  }

  static Uint8List _xor(Uint8List a, Uint8List b) {
    return Uint8List.fromList([for (var i = 0; i < a.length; i++) a[i] ^ b[i]]);
  }

  static BigInt _bytesToInt(List<int> bytes) {
    return BigInt.parse(_bytesToHex(bytes), radix: 16);
  }

  static Uint8List _bytes32(BigInt value) {
    final hex = value.toRadixString(16).padLeft(64, '0');
    return _hexToBytes(hex, expectedLength: 32);
  }

  static Uint8List _hexToBytes(String hex, {int? expectedLength}) {
    final lower = hex.toLowerCase();
    if (!RegExp(r'^[0-9a-f]+$').hasMatch(lower) || lower.length.isOdd) {
      throw ArgumentError('Expected hex string');
    }
    final bytes = Uint8List.fromList([
      for (var i = 0; i < lower.length; i += 2)
        int.parse(lower.substring(i, i + 2), radix: 16),
    ]);
    if (expectedLength != null && bytes.length != expectedLength) {
      throw ArgumentError('Expected $expectedLength bytes');
    }
    return bytes;
  }

  static String _bytesToHex(List<int> bytes) {
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
}

class _Point {
  final BigInt x;
  final BigInt y;

  const _Point(this.x, this.y);
}
