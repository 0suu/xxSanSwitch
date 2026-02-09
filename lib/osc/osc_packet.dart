class OscMessage {
  final String address;
  final List<Object?> arguments;

  const OscMessage(this.address, [this.arguments = const []]);

  @override
  String toString() => 'OscMessage($address, $arguments)';
}

