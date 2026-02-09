import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'vrchat_osc_bridge.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  ThemeMode _themeMode = ThemeMode.system;

  void _setThemeMode(ThemeMode mode) {
    setState(() {
      _themeMode = mode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VRChat OSC AvatarMover Bridge',
      themeAnimationDuration: Duration.zero,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: _themeMode,
      home: OscBridgePage(onThemeToggle: _setThemeMode),
    );
  }
}

class OscBridgePage extends StatefulWidget {
  const OscBridgePage({super.key, required this.onThemeToggle});

  final ValueChanged<ThemeMode> onThemeToggle;

  @override
  State<OscBridgePage> createState() => _OscBridgePageState();
}

class _OscBridgePageState extends State<OscBridgePage> {
  static const String _defaultSendHost = '127.0.0.1';
  static const int _defaultSendPort = 9000;
  static const int _defaultListenPort = 9001;
  static const int _minPort = 1;
  static const int _maxPort = 65535;

  final _sendHostController = TextEditingController(text: _defaultSendHost);
  final _sendPortController = TextEditingController(
    text: _defaultSendPort.toString(),
  );
  final _listenPortController = TextEditingController(
    text: _defaultListenPort.toString(),
  );

  late final VrchatOscBridge _bridge;
  bool _rebuildPending = false;

  @override
  void initState() {
    super.initState();
    _bridge = VrchatOscBridge()..addListener(_onBridgeUpdate);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _bridge.isRunning) return;
      unawaited(_start());
    });
  }

  @override
  void dispose() {
    _bridge.removeListener(_onBridgeUpdate);
    _bridge.dispose();
    _sendHostController.dispose();
    _sendPortController.dispose();
    _listenPortController.dispose();
    super.dispose();
  }

  void _onBridgeUpdate() {
    if (!mounted || _rebuildPending) return;
    _rebuildPending = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _rebuildPending = false;
      if (mounted) setState(() {});
    });
  }

  Future<void> _start() async {
    final sendHostText = _sendHostController.text.trim();
    final sendPortText = _sendPortController.text.trim();
    final listenPortText = _listenPortController.text.trim();

    final sendHost = sendHostText.isEmpty ? _defaultSendHost : sendHostText;
    final sendPort =
        sendPortText.isEmpty ? _defaultSendPort : int.tryParse(sendPortText);
    final listenPort =
        listenPortText.isEmpty ? _defaultListenPort : int.tryParse(listenPortText);

    if (sendPort == null || listenPort == null) {
      _showSnackBar('送信先/受信ポート設定が不正です');
      return;
    }

    if (sendPort < _minPort || sendPort > _maxPort || listenPort < _minPort || listenPort > _maxPort) {
      _showSnackBar('ポート番号は$_minPort〜$_maxPortで入力してください');
      return;
    }

    if (_sendHostController.text.trim() != sendHost) {
      _sendHostController.text = sendHost;
    }
    if (_sendPortController.text.trim() != sendPort.toString()) {
      _sendPortController.text = sendPort.toString();
    }
    if (_listenPortController.text.trim() != listenPort.toString()) {
      _listenPortController.text = listenPort.toString();
    }

    try {
      await _bridge.start(
        listenPort: listenPort,
        sendHost: sendHost,
        sendPort: sendPort,
      );
    } catch (e) {
      _showSnackBar('開始できません: $e');
    }
  }

  Future<void> _stop() async {
    try {
      await _bridge.stop();
    } catch (e) {
      _showSnackBar('停止できません: $e');
    }
  }

  void _showSnackBar(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _resetConnectionFields() {
    if (_bridge.isRunning) return;
    _sendHostController.text = _defaultSendHost;
    _sendPortController.text = _defaultSendPort.toString();
    _listenPortController.text = _defaultListenPort.toString();
    FocusScope.of(context).unfocus();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRunning = _bridge.isRunning;
    final isDark = theme.brightness == Brightness.dark;
    final nextMode = isDark ? ThemeMode.light : ThemeMode.dark;
    final nextModeLabel = isDark ? 'Light' : 'Dark';

    return Scaffold(
      floatingActionButton: FloatingActionButton.small(
        onPressed: () {
          widget.onThemeToggle(nextMode);
        },
        tooltip: nextModeLabel,
        child: Text(
          nextModeLabel,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: 160,
                          child: TextField(
                            controller: _sendHostController,
                            enabled: !isRunning,
                            decoration: const InputDecoration(
                              labelText: 'VRChat Host',
                              hintText: _defaultSendHost,
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 110,
                          child: TextField(
                            controller: _sendPortController,
                            enabled: !isRunning,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'VRChat Port',
                              hintText: _defaultSendPort.toString(),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 110,
                          child: TextField(
                            controller: _listenPortController,
                            enabled: !isRunning,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Listen Port',
                              hintText: _defaultListenPort.toString(),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        OutlinedButton.icon(
                          onPressed: isRunning ? null : _resetConnectionFields,
                          icon: const Icon(Icons.restart_alt),
                          label: const Text('Reset'),
                        ),
                        FilledButton(
                          onPressed: isRunning
                              ? null
                              : () {
                                  _start();
                                },
                          child: const Text('Start'),
                        ),
                        OutlinedButton(
                          onPressed: isRunning
                              ? () {
                                  _stop();
                                }
                              : null,
                          child: const Text('Stop'),
                        ),
                        OutlinedButton(
                          onPressed: isRunning
                              ? () {
                                  _bridge.stopAll();
                                }
                              : null,
                          child: const Text('Stop All'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isRunning ? 'Status: RUNNING' : 'Status: STOPPED',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: isRunning ? Colors.green : Colors.red,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'RX count: ${_bridge.rxCount} / TX count: ${_bridge.txCount}\n'
                      'Last RX: ${_bridge.lastReceived ?? "-"}\n'
                      'Last TX: ${_bridge.lastSent ?? "-"}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
