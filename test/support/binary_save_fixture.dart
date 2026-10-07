import 'dart:convert';
import 'dart:typed_data';

import 'binary_header_fixture.dart';

/// Builds the small subset of HOI4bin tokens used by parser tests.
///
/// The byte layout mirrors the on-disk format: a typed key, equality token,
/// typed value, and 0x0004 to close an object. No user save is a test fixture.
class BinarySaveFixture {
  BinarySaveFixture({String player = 'GER'})
    : _bytes = [...binaryHeader(player: player)];

  final List<int> _bytes;

  List<int> build() => List<int>.unmodifiable(_bytes);

  void addRaw(Iterable<int> bytes) => _bytes.addAll(bytes);

  void fieldInt32(int token, int value) {
    _field(token, 0x000C);
    _int32(value);
  }

  void fieldFixed(int token, double value) {
    _field(token, 0x000D);
    final scaled = (value * 100000).round();
    final payload = ByteData(8)..setInt64(0, scaled, Endian.little);
    _bytes.addAll(payload.buffer.asUint8List());
  }

  void fieldBool(int token, bool value) {
    _field(token, 0x000E);
    _bytes.add(value ? 1 : 0);
  }

  void fieldString(int token, String value) {
    _field(token, 0x000F);
    _string(value);
  }

  void object(int token, void Function(BinarySaveFixture) body) {
    _field(token, 0x0003);
    body(this);
    _uint16(0x0004);
  }

  void intKeyObject(int key, void Function(BinarySaveFixture) body) {
    _uint16(0x000C);
    _int32(key);
    _valueObject(body);
  }

  void stringKeyObject(String key, void Function(BinarySaveFixture) body) {
    _uint16(0x000F);
    _string(key);
    _valueObject(body);
  }

  void unquotedKeyObject(String key, void Function(BinarySaveFixture) body) {
    _uint16(0x0017);
    _string(key);
    _valueObject(body);
  }

  void _valueObject(void Function(BinarySaveFixture) body) {
    _uint16(0x0001);
    _uint16(0x0003);
    body(this);
    _uint16(0x0004);
  }

  void _field(int token, int valueType) {
    _uint16(token);
    _uint16(0x0001);
    _uint16(valueType);
  }

  void _string(String value) {
    final encoded = utf8.encode(value);
    _uint16(encoded.length);
    _bytes.addAll(encoded);
  }

  void _uint16(int value) {
    _bytes.add(value & 0xFF);
    _bytes.add((value >> 8) & 0xFF);
  }

  void _int32(int value) {
    final payload = ByteData(4)..setInt32(0, value, Endian.little);
    _bytes.addAll(payload.buffer.asUint8List());
  }
}
