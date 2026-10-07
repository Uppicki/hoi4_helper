import 'dart:convert';

List<int> binaryHeader({int dateCode = 60759374, String player = 'GER'}) {
  final bytes = <int>[...ascii.encode('HOI4bin')];
  void u16(int value) => bytes.addAll([value & 255, (value >> 8) & 255]);
  void fieldString(int key, int type, String value) {
    u16(key);
    u16(1);
    u16(type);
    final encoded = utf8.encode(value);
    u16(encoded.length);
    bytes.addAll(encoded);
  }

  fieldString(0x2A35, 0x000F, player);
  fieldString(0x2E3E, 0x0017, 'fascism');
  u16(0x284A);
  u16(1);
  u16(0x000C);
  bytes.addAll([
    dateCode & 255,
    (dateCode >> 8) & 255,
    (dateCode >> 16) & 255,
    (dateCode >> 24) & 255,
  ]);
  fieldString(0x299F, 0x000F, 'normal');
  fieldString(0x00EE, 0x000F, 'Case Green v1.18.0.0');
  return bytes;
}
