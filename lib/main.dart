import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'stickman_3d.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stickman 3D Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const StickmanEditorPage(),
    );
  }
}

class StickmanEditorPage extends StatefulWidget {
  const StickmanEditorPage({super.key});

  @override
  State<StickmanEditorPage> createState() => _StickmanEditorPageState();
}

class _StickmanEditorPageState extends State<StickmanEditorPage>
    with SingleTickerProviderStateMixin {
  late StickmanController _controller;
  late Ticker _ticker;
  double _lastTime = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = StickmanController(scale: 1.0);
    // Start with PoseMotionStrategy (editor friendly)
    // Wait, the editor sets this itself in initState.
    // But we need to pump updates for `lerp` to work if we were using it.
    // The editor uses Drag to update positions directly.

    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final double currentTime = elapsed.inMilliseconds / 1000.0;
    final double dt = currentTime - _lastTime;
    _lastTime = currentTime;

    setState(() {
      // We still call update so any physics/interpolation runs
      _controller.update(dt, 0.0, 0.0);
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stickman Editor'),
      ),
      body: StickmanPoseEditor(controller: _controller),
    );
  }
}
