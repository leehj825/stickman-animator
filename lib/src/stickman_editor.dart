import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' as v;
import 'stickman_skeleton.dart';
import 'stickman_animator.dart';
import 'stickman_painter.dart';

class StickmanPoseEditor extends StatefulWidget {
  final StickmanController controller;

  const StickmanPoseEditor({Key? key, required this.controller}) : super(key: key);

  @override
  State<StickmanPoseEditor> createState() => _StickmanPoseEditorState();
}

class _StickmanPoseEditorState extends State<StickmanPoseEditor> {
  // Mapping of bone names to their Vector3 objects in the skeleton
  late Map<String, v.Vector3> _boneMap;
  String? _draggedBone;

  @override
  void initState() {
    super.initState();
    _initBoneMap();

    // Set to ManualMotionStrategy to allow dragging without fighting with procedural logic or lerp
    widget.controller.setStrategy(ManualMotionStrategy());
  }

  void _initBoneMap() {
    final skel = widget.controller.skeleton;
    _boneMap = {
      'Hip': skel.hip,
      'Neck': skel.neck,
      'L.Shoulder': skel.lShoulder,
      'R.Shoulder': skel.rShoulder,
      'L.Hip': skel.lHip,
      'R.Hip': skel.rHip,
      'L.Knee': skel.lKnee,
      'R.Knee': skel.rKnee,
      'L.Foot': skel.lFoot,
      'R.Foot': skel.rFoot,
      'L.Elbow': skel.lElbow,
      'R.Elbow': skel.rElbow,
      'L.Hand': skel.lHand,
      'R.Hand': skel.rHand,
    };
  }

  // Coordinate Mapping matching StickmanPainter
  Offset _toScreen(v.Vector3 vec, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final scaled = Offset(vec.x, vec.y + (vec.z * 0.3)) * widget.controller.scale;
    return center + scaled;
  }

  // Inverse Mapping (Simplified)
  void _updateBonePosition(String boneName, Offset delta) {
    if (!_boneMap.containsKey(boneName)) return;

    final bone = _boneMap[boneName]!;
    final scale = widget.controller.scale;
    if (scale == 0) return;

    // Direct update of the skeleton vectors
    bone.x += delta.dx / scale;
    bone.y += delta.dy / scale;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return Stack(
          children: [
            // Bottom: The Painter
            Positioned.fill(
              child: CustomPaint(
                painter: StickmanPainter(controller: widget.controller),
              ),
            ),

            // Top: Draggable Handles
            ..._boneMap.keys.map((name) {
              final bone = _boneMap[name]!;
              final screenPos = _toScreen(bone, size);

              return Positioned(
                left: screenPos.dx - 10,
                top: screenPos.dy - 10,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _updateBonePosition(name, details.delta);
                    });
                  },
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.5),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              );
            }).toList(),

            // UI Controls
            Positioned(
              bottom: 20,
              right: 20,
              child: ElevatedButton(
                onPressed: _copyPoseToClipboard,
                child: const Text("Copy Pose to Clipboard"),
              ),
            ),
          ],
        );
      },
    );
  }

  void _copyPoseToClipboard() {
    final skel = widget.controller.skeleton;
    final buffer = StringBuffer();

    String format(v.Vector3 v) => "${v.x.toStringAsFixed(1)}, ${v.y.toStringAsFixed(1)}, ${v.z.toStringAsFixed(1)}";

    buffer.writeln("..hip.setValues(${format(skel.hip)})");
    buffer.writeln("..neck.setValues(${format(skel.neck)})");
    buffer.writeln("..lShoulder.setValues(${format(skel.lShoulder)})");
    buffer.writeln("..rShoulder.setValues(${format(skel.rShoulder)})");
    buffer.writeln("..lHip.setValues(${format(skel.lHip)})");
    buffer.writeln("..rHip.setValues(${format(skel.rHip)})");
    buffer.writeln("..lKnee.setValues(${format(skel.lKnee)})");
    buffer.writeln("..rKnee.setValues(${format(skel.rKnee)})");
    buffer.writeln("..lFoot.setValues(${format(skel.lFoot)})");
    buffer.writeln("..rFoot.setValues(${format(skel.rFoot)})");
    buffer.writeln("..lElbow.setValues(${format(skel.lElbow)})");
    buffer.writeln("..rElbow.setValues(${format(skel.rElbow)})");
    buffer.writeln("..lHand.setValues(${format(skel.lHand)})");
    buffer.writeln("..rHand.setValues(${format(skel.rHand)})");

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Pose copied to clipboard!")),
    );
  }
}
