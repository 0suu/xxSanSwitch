import 'dart:async';

import 'osc/osc_packet.dart';

abstract class OscOutput {
  void send(OscMessage message);
}

enum AvatarMoverInputType {
  // Movement
  moveForward,
  moveBackward,
  moveRight,
  moveLeft,
  jump,

  // View
  lookRight,
  lookLeft,
  comfortRight,
  comfortLeft,

  voice,

  unknown,
}

class AvatarMover {
  final OscOutput _output;
  final Duration tickInterval;
  final double activeThreshold;
  final Duration actionPulseDuration;

  AvatarMover(
    this._output, {
    this.tickInterval = const Duration(milliseconds: 16),
    this.activeThreshold = 0.999,
    this.actionPulseDuration = const Duration(milliseconds: 1000),
  }) {
    for (final type in _inputTypeAddress.keys) {
      _moveStates[type] = _MoveState();
    }
  }

  final Map<AvatarMoverInputType, String> _inputTypeAddress = const {
    AvatarMoverInputType.moveForward: '/input/MoveForward',
    AvatarMoverInputType.moveBackward: '/input/MoveBackward',
    AvatarMoverInputType.moveRight: '/input/MoveRight',
    AvatarMoverInputType.moveLeft: '/input/MoveLeft',
    AvatarMoverInputType.jump: '/input/Jump',
    AvatarMoverInputType.lookRight: '/input/LookRight',
    AvatarMoverInputType.lookLeft: '/input/LookLeft',
    AvatarMoverInputType.comfortRight: '/input/ComfortRight',
    AvatarMoverInputType.comfortLeft: '/input/ComfortLeft',
    AvatarMoverInputType.voice: '/input/Voice',
  };

  final Map<AvatarMoverInputType, _MoveState> _moveStates = {};
  bool _allStopFlag = false;
  final List<Timer> _pulseTimers = <Timer>[];

  void dispose() {
    for (final state in _moveStates.values) {
      state.timer?.cancel();
      state.timer = null;
      state.isMoving = false;
    }
    for (final t in _pulseTimers) {
      t.cancel();
    }
    _pulseTimers.clear();
  }

  void move(AvatarMoverInputType type, double value) {
    if (type == AvatarMoverInputType.unknown) return;

    final state = _moveStates[type];
    if (state == null) return;

    final clamped = value.clamp(0.0, 1.0);
    final isActive = clamped >= activeThreshold;

    // Jump / Voice are treated like the original C# implementation:
    // when the input becomes active, send 1 and force-release after a fixed duration.
    if (type == AvatarMoverInputType.jump || type == AvatarMoverInputType.voice) {
      if (isActive) {
        _pulse(type);
      }
      return;
    }

    state.isMoving = isActive;

    if (!isActive) {
      // Mirror C# behavior: stop is applied by the running loop,
      // which then sends 0 once before finishing.
      return;
    }

    // Start sending continuously while moving.
    if (state.timer != null) return;
    _send(type, 1);
    state.timer = Timer.periodic(tickInterval, (_) {
      if (_allStopFlag || !state.isMoving) {
        state.timer?.cancel();
        state.timer = null;
        _send(type, 0);
        return;
      }
      _send(type, 1);
    });
  }

  Future<void> stopAll() async {
    _allStopFlag = true;

    for (final entry in _moveStates.entries) {
      entry.value.isMoving = false;
      entry.value.timer?.cancel();
      entry.value.timer = null;
    }

    for (final type in _inputTypeAddress.keys) {
      if (type == AvatarMoverInputType.voice) continue;
      _send(type, 0);
    }

    // Mirror the C# behavior (yield once, then allow movement again).
    await Future<void>.delayed(Duration.zero);
    _allStopFlag = false;
  }

  void _pulse(AvatarMoverInputType type) {
    _send(type, 1);
    late final Timer timer;
    timer = Timer(actionPulseDuration, () {
      _send(type, 0);
      _pulseTimers.remove(timer);
    });
    _pulseTimers.add(timer);
  }

  void _send(AvatarMoverInputType type, int value) {
    final address = _inputTypeAddress[type];
    if (address == null) return;
    _output.send(OscMessage(address, [value]));
  }
}

class _MoveState {
  bool isMoving = false;
  Timer? timer;
}
