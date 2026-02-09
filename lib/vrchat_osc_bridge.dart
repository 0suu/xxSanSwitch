import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'avatar_mover.dart';
import 'osc/osc_codec.dart';
import 'osc/osc_packet.dart';
import 'osc/osc_udp.dart';

class VrchatOscBridge extends ChangeNotifier implements OscOutput {
  bool _disposed = false;
  bool _isRunning = false;
  bool get isRunning => _isRunning;

  String? lastReceived;
  String? lastSent;
  int rxCount = 0;
  int txCount = 0;

  OscUdpSender? _sender;
  OscUdpReceiver? _receiver;
  StreamSubscription<Uint8List>? _subscription;
  AvatarMover? _avatarMover;
  final Map<String, Object?> _lastTxArgByAddress = <String, Object?>{};

  Future<void> start({
    required int listenPort,
    required String sendHost,
    required int sendPort,
  }) async {
    if (_disposed) {
      throw StateError('VrchatOscBridge is disposed');
    }
    if (_isRunning) return;

    final remoteAddress =
        InternetAddress.tryParse(sendHost) ??
        (await InternetAddress.lookup(sendHost)).first;
    final sender = OscUdpSender(remoteAddress: remoteAddress, remotePort: sendPort);
    final receiver = OscUdpReceiver(listenPort: listenPort);

    await sender.start();
    await receiver.start();

    _sender = sender;
    _receiver = receiver;
    _avatarMover = AvatarMover(this);

    _subscription = receiver.datagrams.listen(
      (datagram) {
        List<OscMessage> messages;
        try {
          messages = OscCodec.decode(datagram);
        } catch (e) {
          return;
        }

        for (final msg in messages) {
          _handleMessage(msg);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('OSC UDP receive error: $error');
        if (_disposed) return;
        lastReceived = 'UDP受信エラー: $error';
        notifyListeners();
      },
    );

    _isRunning = true;
    if (!_disposed) notifyListeners();
  }

  Future<void> stop() async {
    await _stopInternal(notify: true);
  }

  Future<void> _stopInternal({required bool notify}) async {
    if (!_isRunning) return;

    await _subscription?.cancel();
    _subscription = null;

    await _receiver?.dispose();
    _receiver = null;

    await _sender?.stop();
    _sender = null;

    _avatarMover?.dispose();
    _avatarMover = null;

    _isRunning = false;
    if (notify && !_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    // Best-effort cleanup without awaiting.
    unawaited(_stopInternal(notify: false));
    super.dispose();
  }

  Future<void> stopAll() async {
    await _avatarMover?.stopAll();
  }

  @override
  void send(OscMessage message) {
    if (_disposed) return;
    final sender = _sender;
    if (sender == null) return;
    final data = OscCodec.encodeMessage(message);
    final sentBytes = sender.send(data);
    txCount += 1;

    final arg = message.arguments.isNotEmpty ? message.arguments.first : null;
    final prevArg = _lastTxArgByAddress[message.address];
    _lastTxArgByAddress[message.address] = arg;

    // Avoid flooding UI/logs for "held" inputs that are sent repeatedly.
    final isDuplicate = prevArg == arg;
    if (!isDuplicate) {
      lastSent = '${message.address} ${arg ?? ""}'.trim();
      notifyListeners();
    } else {
      lastSent = '${message.address} ${arg ?? ""}'.trim();
    }
  }

  void _handleMessage(OscMessage message) {
    if (_disposed) return;
    final address = message.address;
    if (!address.contains('/avatar/parameters/sai.AM')) {
      return;
    }

    final value = _firstArgAsDouble(message.arguments);
    if (value == null) return;

    rxCount += 1;
    lastReceived = '$address $value';

    final type = _mapAvatarMover(address);
    if (type == AvatarMoverInputType.unknown) {
      notifyListeners();
      return;
    }
    _avatarMover?.move(type, value);

    notifyListeners();
  }

  AvatarMoverInputType _mapAvatarMover(String address) {
    final name = address.split('/').last;
    return switch (name) {
      'sai.AMForward' => AvatarMoverInputType.moveForward,
      'sai.AMBack' => AvatarMoverInputType.moveBackward,
      'sai.AMBackward' => AvatarMoverInputType.moveBackward,
      'sai.AMRight' => AvatarMoverInputType.moveRight,
      'sai.AMLeft' => AvatarMoverInputType.moveLeft,
      'sai.AMJump' => AvatarMoverInputType.jump,
      'sai.AMLookRight' => AvatarMoverInputType.lookRight,
      'sai.AMLookLeft' => AvatarMoverInputType.lookLeft,
      'sai.AMMic' => AvatarMoverInputType.voice,
      _ => AvatarMoverInputType.unknown,
    };
  }

  double? _firstArgAsDouble(List<Object?> args) {
    if (args.isEmpty) return null;
    final a = args.first;
    return switch (a) {
      null => null,
      bool b => b ? 1.0 : 0.0,
      int i => i.toDouble(),
      double d => d,
      _ => null,
    };
  }
}
