import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

class OscUdpSender {
  final InternetAddress remoteAddress;
  final int remotePort;
  RawDatagramSocket? _socket;

  OscUdpSender({
    required this.remoteAddress,
    required this.remotePort,
  });

  Future<void> start() async {
    _socket ??= await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  }

  int send(Uint8List bytes) {
    final socket = _socket;
    if (socket == null) {
      throw StateError('OscUdpSender is not started');
    }
    return socket.send(bytes, remoteAddress, remotePort);
  }

  Future<void> stop() async {
    _socket?.close();
    _socket = null;
  }
}

class OscUdpReceiver {
  final int listenPort;
  RawDatagramSocket? _socket;
  final _controller = StreamController<Uint8List>.broadcast();

  OscUdpReceiver({required this.listenPort});

  Stream<Uint8List> get datagrams => _controller.stream;

  Future<void> start() async {
    if (_socket != null) return;
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, listenPort);
    _socket = socket;

    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? datagram;
      while ((datagram = socket.receive()) != null) {
        _controller.add(datagram!.data);
      }
    }, onError: (Object error, StackTrace stackTrace) {
      _controller.addError(error, stackTrace);
    });
  }

  Future<void> stop() async {
    _socket?.close();
    _socket = null;
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}
