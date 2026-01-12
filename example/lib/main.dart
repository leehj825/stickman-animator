import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:stickman_3d/stickman_3d.dart';

void main() {
  runApp(const MaterialApp(home: ExampleGameScreen()));
}

class ExampleGameScreen extends StatelessWidget {
  const ExampleGameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Stickman Integration Example")),
      body: const Center(
        // Ensure 'assets/stickman.sap' exists in your example/assets folder
        child: GameCharacterWidget(assetPath: 'assets/stickman.sap'),
      ),
    );
  }
}

// --- REUSABLE GAME WIDGET ---

class GameCharacterWidget extends StatefulWidget {
  final String assetPath;
  final String animationName;

  const GameCharacterWidget({
    super.key,
    required this.assetPath,
    this.animationName = "Run"
  });

  @override
  State<GameCharacterWidget> createState() => _GameCharacterWidgetState();
}

class _GameCharacterWidgetState extends State<GameCharacterWidget>
    with SingleTickerProviderStateMixin {

  late StickmanController _controller;
  late Ticker _ticker;
  double _lastTime = 0.0;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _controller = StickmanController(scale: 0.5);
    _ticker = createTicker(_onTick)..start();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final jsonString = await rootBundle.loadString(widget.assetPath);
      final jsonMap = jsonDecode(jsonString);
      List<StickmanClip> clips;

      if (jsonMap is Map<String, dynamic> && jsonMap.containsKey('clips')) {
        clips = (jsonMap['clips'] as List).map((c) => StickmanClip.fromJson(c)).toList();
      } else {
        clips = [StickmanClip.fromJson(jsonMap)];
      }

      final clip = clips.firstWhere(
        (c) => c.name == widget.animationName,
        orElse: () => clips.first
      );

      setState(() {
        _controller.activeClip = clip;
        _controller.setMode(EditorMode.animate);
        _controller.isPlaying = true;
        _isLoaded = true;
      });
    } catch (e) {
      debugPrint("Error loading stickman: $e");
    }
  }

  void _onTick(Duration elapsed) {
    if (!_isLoaded) return;
    final double currentTime = elapsed.inMilliseconds / 1000.0;
    final double dt = currentTime - _lastTime;
    _lastTime = currentTime;

    _controller.update(dt, 0.0, 0.0);
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded) return const SizedBox(width: 50, height: 100, child: CircularProgressIndicator());

    return SizedBox(
      width: 300,
      height: 300,
      child: CustomPaint(
        painter: StickmanPainter(
          controller: _controller,
          cameraView: CameraView.side,
          color: Colors.black,
        ),
      ),
    );
  }
}
