import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:xx_san_swtich/osc/osc_codec.dart';
import 'package:xx_san_swtich/osc/osc_packet.dart';

void main() {
  test('encode/decode float message roundtrip', () {
    final bytes = OscCodec.encodeFloat('/input/MoveForward', 1.0);
    final decoded = OscCodec.decode(bytes);

    expect(decoded, hasLength(1));
    expect(decoded.first.address, '/input/MoveForward');
    expect(decoded.first.arguments, hasLength(1));
    expect((decoded.first.arguments.first as num).toDouble(), closeTo(1.0, 1e-6));
  });

  test('decode bundle flattens messages', () {
    final m1 = OscCodec.encodeMessage(const OscMessage('/a', [1]));
    final m2 = OscCodec.encodeMessage(const OscMessage('/b', [2.0]));

    final bundle = _buildBundle([m1, m2]);
    final decoded = OscCodec.decode(bundle);

    expect(decoded.map((m) => m.address).toList(), ['/a', '/b']);
  });
}

Uint8List _buildBundle(List<Uint8List> elements) {
  final builder = BytesBuilder(copy: false);

  // "#bundle" string with padding
  builder.add(_oscString('#bundle'));
  builder.add(Uint8List(8)); // timetag (0)

  for (final element in elements) {
    final size = ByteData(4)..setInt32(0, element.length, Endian.big);
    builder.add(size.buffer.asUint8List());
    builder.add(element);
  }

  return builder.takeBytes();
}

Uint8List _oscString(String s) {
  final bytes = Uint8List.fromList(s.codeUnits);
  final withNull = Uint8List(bytes.length + 1)..setAll(0, bytes);
  final pad = (4 - (withNull.length % 4)) % 4;
  if (pad == 0) return withNull;
  final padded = Uint8List(withNull.length + pad)..setAll(0, withNull);
  return padded;
}

