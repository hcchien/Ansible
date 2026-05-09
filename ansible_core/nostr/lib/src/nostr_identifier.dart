import 'dart:convert';

class NostrIdentifier {
  static String encodeNpub(String pubkeyHex) {
    return _Bech32.encode('npub', _convertBits(_hexToBytes(pubkeyHex), 8, 5));
  }

  static String decodeNpub(String npub) {
    return _decodeHexIdentifier(npub, expectedHrp: 'npub');
  }

  static String encodeNote(String eventIdHex) {
    return _Bech32.encode('note', _convertBits(_hexToBytes(eventIdHex), 8, 5));
  }

  static String decodeNote(String note) {
    return _decodeHexIdentifier(note, expectedHrp: 'note');
  }

  static String encodeNevent(
    String eventIdHex, {
    List<String> relays = const [],
    String? authorPubkeyHex,
    int? kind,
  }) {
    return _Bech32.encode(
      'nevent',
      _convertBits(
        _encodeTlv([
          _tlvBytes(0, _hexToBytes(eventIdHex)),
          for (final relay in relays) _tlvBytes(1, utf8.encode(relay)),
          if (authorPubkeyHex != null)
            _tlvBytes(2, _hexToBytes(authorPubkeyHex)),
          if (kind != null) _tlvBytes(3, _uint32Bytes(kind)),
        ]),
        8,
        5,
      ),
    );
  }

  static String encodeNaddr({
    required String identifier,
    required String pubkeyHex,
    required int kind,
    List<String> relays = const [],
  }) {
    return _Bech32.encode(
      'naddr',
      _convertBits(
        _encodeTlv([
          _tlvBytes(0, utf8.encode(identifier)),
          for (final relay in relays) _tlvBytes(1, utf8.encode(relay)),
          _tlvBytes(2, _hexToBytes(pubkeyHex)),
          _tlvBytes(3, _uint32Bytes(kind)),
        ]),
        8,
        5,
      ),
    );
  }

  static String _decodeHexIdentifier(
    String value, {
    required String expectedHrp,
  }) {
    final decoded = _Bech32.decode(value);
    if (decoded.hrp != expectedHrp) {
      throw ArgumentError('Expected $expectedHrp identifier');
    }
    return _bytesToHex(_convertBits(decoded.data, 5, 8, pad: false));
  }

  static List<int> _hexToBytes(String hex) {
    final lower = hex.toLowerCase();
    if (!RegExp(r'^[0-9a-f]+$').hasMatch(lower) || lower.length.isOdd) {
      throw ArgumentError('Expected even-length hex string');
    }
    return [
      for (var i = 0; i < lower.length; i += 2)
        int.parse(lower.substring(i, i + 2), radix: 16),
    ];
  }

  static List<int> _encodeTlv(List<List<int>> entries) {
    return [for (final entry in entries) ...entry];
  }

  static List<int> _tlvBytes(int type, List<int> value) {
    if (value.length > 255) {
      throw ArgumentError('NIP-19 TLV values must fit in one byte length');
    }
    return [type, value.length, ...value];
  }

  static List<int> _uint32Bytes(int value) {
    if (value < 0 || value > 0xffffffff) {
      throw ArgumentError('NIP-19 kind must fit uint32');
    }
    return [
      (value >> 24) & 0xff,
      (value >> 16) & 0xff,
      (value >> 8) & 0xff,
      value & 0xff,
    ];
  }

  static String _bytesToHex(List<int> bytes) {
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  static List<int> _convertBits(
    List<int> data,
    int fromBits,
    int toBits, {
    bool pad = true,
  }) {
    var acc = 0;
    var bits = 0;
    final result = <int>[];
    final maxv = (1 << toBits) - 1;
    final maxAcc = (1 << (fromBits + toBits - 1)) - 1;

    for (final value in data) {
      if (value < 0 || (value >> fromBits) != 0) {
        throw ArgumentError('Invalid bech32 data value');
      }
      acc = ((acc << fromBits) | value) & maxAcc;
      bits += fromBits;
      while (bits >= toBits) {
        bits -= toBits;
        result.add((acc >> bits) & maxv);
      }
    }

    if (pad) {
      if (bits > 0) result.add((acc << (toBits - bits)) & maxv);
    } else {
      if (bits >= fromBits) throw ArgumentError('Invalid padding');
      if (((acc << (toBits - bits)) & maxv) != 0) {
        throw ArgumentError('Non-zero padding');
      }
    }
    return result;
  }
}

class _Bech32Decoded {
  final String hrp;
  final List<int> data;

  const _Bech32Decoded({required this.hrp, required this.data});
}

class _Bech32 {
  static const _charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
  static final _charsetMap = {
    for (var i = 0; i < _charset.length; i++) _charset[i]: i,
  };

  static String encode(String hrp, List<int> data) {
    final lowerHrp = hrp.toLowerCase();
    final combined = [...data, ..._createChecksum(lowerHrp, data)];
    return '${lowerHrp}1${combined.map((value) => _charset[value]).join()}';
  }

  static _Bech32Decoded decode(String value) {
    final lower = value.toLowerCase();
    if (value != lower && value != value.toUpperCase()) {
      throw ArgumentError('Mixed-case bech32 identifiers are invalid');
    }

    final separator = lower.lastIndexOf('1');
    if (separator < 1 || separator + 7 > lower.length) {
      throw ArgumentError('Invalid bech32 separator');
    }

    final hrp = lower.substring(0, separator);
    final data = lower.substring(separator + 1).split('').map((char) {
      final value = _charsetMap[char];
      if (value == null) throw ArgumentError('Invalid bech32 character');
      return value;
    }).toList();

    if (!_verifyChecksum(hrp, data)) {
      throw ArgumentError('Invalid bech32 checksum');
    }
    return _Bech32Decoded(hrp: hrp, data: data.sublist(0, data.length - 6));
  }

  static List<int> _createChecksum(String hrp, List<int> data) {
    final values = [..._hrpExpand(hrp), ...data, 0, 0, 0, 0, 0, 0];
    final polymod = _polymod(values) ^ 1;
    return [for (var i = 0; i < 6; i++) (polymod >> (5 * (5 - i))) & 31];
  }

  static bool _verifyChecksum(String hrp, List<int> data) {
    return _polymod([..._hrpExpand(hrp), ...data]) == 1;
  }

  static List<int> _hrpExpand(String hrp) {
    return [
      for (final codeUnit in hrp.codeUnits) codeUnit >> 5,
      0,
      for (final codeUnit in hrp.codeUnits) codeUnit & 31,
    ];
  }

  static int _polymod(List<int> values) {
    const generator = [
      0x3b6a57b2,
      0x26508e6d,
      0x1ea119fa,
      0x3d4233dd,
      0x2a1462b3,
    ];
    var chk = 1;
    for (final value in values) {
      final top = chk >> 25;
      chk = ((chk & 0x1ffffff) << 5) ^ value;
      for (var i = 0; i < 5; i++) {
        if (((top >> i) & 1) != 0) chk ^= generator[i];
      }
    }
    return chk;
  }
}
