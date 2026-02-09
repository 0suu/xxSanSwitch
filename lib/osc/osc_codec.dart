import 'dart:convert';
import 'dart:typed_data';

import 'osc_packet.dart';

class OscCodec {
  /// Decode a datagram into OSC messages.
  ///
  /// VRChat typically sends single messages, but bundles may occur, so this
  /// method flattens bundles into a message list.
  static List<OscMessage> decode(Uint8List bytes) {
    final reader = _OscReader(bytes);
    return _decodePacket(reader);
  }

  static Uint8List encodeMessage(OscMessage message) {
    return encodeAddressWithArgs(message.address, message.arguments);
  }

  static Uint8List encodeAddressWithArgs(String address, List<Object?> args) {
    final builder = BytesBuilder(copy: false);

    _writeOscString(builder, address);

    final typeTags = StringBuffer(','); // OSC type tag string must start with ','
    final argData = BytesBuilder(copy: false);

    for (final arg in args) {
      if (arg is bool) {
        typeTags.write(arg ? 'T' : 'F');
        continue;
      }
      if (arg is int) {
        typeTags.write('i');
        final data = ByteData(4)..setInt32(0, arg, Endian.big);
        argData.add(data.buffer.asUint8List());
        continue;
      }
      if (arg is num) {
        typeTags.write('f');
        final data = ByteData(4)..setFloat32(0, arg.toDouble(), Endian.big);
        argData.add(data.buffer.asUint8List());
        continue;
      }
      if (arg is String) {
        typeTags.write('s');
        _writeOscString(argData, arg);
        continue;
      }

      throw ArgumentError('Unsupported OSC argument type: ${arg.runtimeType}');
    }

    _writeOscString(builder, typeTags.toString());
    builder.add(argData.takeBytes());

    return builder.takeBytes();
  }

  static Uint8List encodeFloat(String address, double value) {
    return encodeAddressWithArgs(address, [value]);
  }

  static List<OscMessage> _decodePacket(_OscReader reader) {
    if (reader.isDone) return const [];

    final addressOrBundle = reader.readOscString();
    if (addressOrBundle == '#bundle') {
      reader.readBytes(8); // timetag
      final messages = <OscMessage>[];
      while (!reader.isDone) {
        final size = reader.readInt32();
        if (size <= 0 || reader.remaining < size) break;
        final elementBytes = reader.readBytes(size);
        messages.addAll(decode(elementBytes));
      }
      return messages;
    }

    final address = addressOrBundle;
    final typeTag = reader.readOscString();
    final tags = typeTag.startsWith(',') ? typeTag.substring(1) : typeTag;

    final args = <Object?>[];
    for (final tag in tags.split('')) {
      switch (tag) {
        case '':
          break;
        case 'i':
          args.add(reader.readInt32());
          break;
        case 'f':
          args.add(reader.readFloat32());
          break;
        case 's':
          args.add(reader.readOscString());
          break;
        case 'T':
          args.add(true);
          break;
        case 'F':
          args.add(false);
          break;
        default:
          // Skip unsupported tags conservatively (best-effort decode).
          // For VRChat parameter use-cases, i/f/T/F should be enough.
          return [OscMessage(address, args)];
      }
    }

    return [OscMessage(address, args)];
  }

  static void _writeOscString(BytesBuilder builder, String value) {
    final bytes = utf8.encode(value);
    builder.add(bytes);
    builder.addByte(0);

    final pad = (4 - ((bytes.length + 1) % 4)) % 4;
    for (var i = 0; i < pad; i++) {
      builder.addByte(0);
    }
  }
}

class _OscReader {
  final Uint8List _bytes;
  final ByteData _data;
  int _offset = 0;

  _OscReader(this._bytes) : _data = ByteData.sublistView(_bytes);

  bool get isDone => _offset >= _bytes.length;
  int get remaining => _bytes.length - _offset;

  Uint8List readBytes(int length) {
    final end = _offset + length;
    if (end > _bytes.length) {
      throw RangeError('OSC read beyond buffer: $_offset + $length > ${_bytes.length}');
    }
    final out = Uint8List.sublistView(_bytes, _offset, end);
    _offset = end;
    return out;
  }

  int readInt32() {
    if (remaining < 4) throw RangeError('OSC int32 beyond buffer');
    final value = _data.getInt32(_offset, Endian.big);
    _offset += 4;
    return value;
  }

  double readFloat32() {
    if (remaining < 4) throw RangeError('OSC float32 beyond buffer');
    final value = _data.getFloat32(_offset, Endian.big);
    _offset += 4;
    return value;
  }

  String readOscString() {
    final start = _offset;
    var end = start;
    while (end < _bytes.length && _bytes[end] != 0) {
      end++;
    }
    if (end >= _bytes.length) {
      throw FormatException('Unterminated OSC string at offset $start');
    }

    final value = utf8.decode(_bytes.sublist(start, end));
    _offset = end + 1; // skip null
    _align4();
    return value;
  }

  void _align4() {
    final mod = _offset % 4;
    if (mod != 0) _offset += (4 - mod);
  }
}

