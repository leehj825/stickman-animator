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
      home: const StickmanDemo(),
    );
  }
}

class StickmanDemo extends StatefulWidget {
  const StickmanDemo({super.key});

  @override
  State<StickmanDemo> createState() => _StickmanDemoState();
}

class _StickmanDemoState extends State<StickmanDemo>
    with SingleTickerProviderStateMixin {
  late StickmanController _controller;
  late Ticker _ticker;
  double _lastTime = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = StickmanController();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final double currentTime = elapsed.inMilliseconds / 1000.0;
    final double dt = currentTime - _lastTime;
    _lastTime = currentTime;

    // Simulate some movement
    setState(() {
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
        title: const Text('Stickman 3D Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: CustomPaint(
          painter: StickmanPainter(controller: _controller),
          size: const Size(300, 300),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
            if (_controller.state == StickmanState.ragdoll) {
                _controller.respawn();
            } else {
                _controller.die();
            }
        },
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
