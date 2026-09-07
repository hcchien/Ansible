List<int> ecdsaDerSignatureToJose(List<int> der) {
  if (der.length < 8 || der[0] != 0x30) {
    throw const FormatException('Invalid ECDSA DER signature.');
  }
  var offset = 1;
  final sequenceLength = _derLength(der, offset);
  offset = sequenceLength.$2;
  if (offset + sequenceLength.$1 != der.length || der[offset++] != 0x02) {
    throw const FormatException('Invalid ECDSA DER signature.');
  }
  final rLength = _derLength(der, offset);
  offset = rLength.$2;
  if (offset + rLength.$1 >= der.length) {
    throw const FormatException('Invalid ECDSA DER signature.');
  }
  final r = der.sublist(offset, offset + rLength.$1);
  offset += rLength.$1;
  if (der[offset++] != 0x02) {
    throw const FormatException('Invalid ECDSA DER signature.');
  }
  final sLength = _derLength(der, offset);
  offset = sLength.$2;
  if (offset + sLength.$1 != der.length) {
    throw const FormatException('Invalid ECDSA DER signature.');
  }
  final s = der.sublist(offset, offset + sLength.$1);
  return [..._unsigned32(r), ..._unsigned32(s)];
}

(int, int) _derLength(List<int> bytes, int offset) {
  if (offset >= bytes.length) {
    throw const FormatException('Invalid DER length.');
  }
  final first = bytes[offset++];
  if (first < 0x80) return (first, offset);
  final count = first & 0x7f;
  if (count < 1 || count > 2 || offset + count > bytes.length) {
    throw const FormatException('Invalid DER length.');
  }
  var length = 0;
  for (var i = 0; i < count; i++) {
    length = (length << 8) | bytes[offset++];
  }
  return (length, offset);
}

List<int> _unsigned32(List<int> integer) {
  var value = integer;
  while (value.length > 32 && value.first == 0) {
    value = value.sublist(1);
  }
  if (value.length > 32) {
    throw const FormatException('ECDSA integer is too large.');
  }
  return [...List<int>.filled(32 - value.length, 0), ...value];
}
