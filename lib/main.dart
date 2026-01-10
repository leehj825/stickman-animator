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
    // User asked to "make initial stick man larger".
    // We handle view zoom in the editor, but setting a larger base scale here is also good.
    // However, the editor now defaults _zoom to 2.0.
    // Let's keep scale 1.0 here to avoid double scaling issues if logic assumes 1.0.
    _controller = StickmanController(scale: 1.0);

    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final double currentTime = elapsed.inMilliseconds / 1000.0;
    final double dt = currentTime - _lastTime;
    _lastTime = currentTime;

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
    // We don't need Scaffold/AppBar here because StickmanPoseEditor now provides its own full screen view/scaffold background
    // But StickmanPoseEditor returns a LayoutBuilder/Scaffold.
    // So we can just return it.
    return StickmanPoseEditor(controller: _controller);
  }
}
