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
  final TransformationController _transformationController = TransformationController();

  @override
  void initState() {
    super.initState();
    _initBoneMap();

    // Set to ManualMotionStrategy to allow dragging without fighting with procedural logic or lerp
    widget.controller.setStrategy(ManualMotionStrategy());
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
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

  // Coordinate Mapping matching StickmanPainter + InteractiveViewer Transform
  Offset _toScreen(v.Vector3 vec, Size size) {
    // 1. Calculate Local Canvas Position (as per StickmanPainter)
    final center = Offset(size.width / 2, size.height / 2);
    final localPos = center + (Offset(vec.x, vec.y + (vec.z * 0.3)) * widget.controller.scale);

    // 2. Apply InteractiveViewer Transform
    // The matrix works on 3D points, but here we work on 2D offsets.
    // Matrix4.transform3(Vector3) is the usual way.
    final matrix = _transformationController.value;
    final transformed = MatrixUtils.transformPoint(matrix, localPos);

    return transformed;
  }

  // Inverse Mapping
  void _updateBonePosition(String boneName, Offset delta) {
    if (!_boneMap.containsKey(boneName)) return;

    final bone = _boneMap[boneName]!;
    final modelScale = widget.controller.scale;
    if (modelScale == 0) return;

    // We need to account for the View Scale (Zoom)
    // Dragging 10px on screen corresponds to (10 / Zoom) in the canvas space.
    final viewScale = _transformationController.value.getMaxScaleOnAxis();

    // Update bone
    bone.x += delta.dx / (modelScale * viewScale);
    bone.y += delta.dy / (modelScale * viewScale);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);

        return Stack(
          children: [
            // Layer 1: The Zoomable Editor View
            InteractiveViewer(
              transformationController: _transformationController,
              maxScale: 5.0,
              minScale: 0.1,
              boundaryMargin: const EdgeInsets.all(double.infinity),
              constrained: true, // Use viewport constraints, painter centers itself
              onInteractionUpdate: (details) {
                 // Trigger rebuild to update handle positions as we zoom/pan
                 setState(() {});
              },
              child: SizedBox(
                 width: size.width,
                 height: size.height,
                 child: CustomPaint(
                   painter: StickmanPainter(controller: widget.controller),
                 ),
              ),
            ),

            // Layer 2: Draggable Handles (Overlay)
            // These are drawn *outside* InteractiveViewer so they stay constant size.
            // We manually map their positions using _toScreen().
            ..._boneMap.keys.map((name) {
              final bone = _boneMap[name]!;
              final screenPos = _toScreen(bone, size);

              // Only draw if within bounds? No, let them bleed or clip naturally.

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

            // Layer 3: UI Controls
            Align(
              alignment: Alignment.bottomRight,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: ElevatedButton(
                    onPressed: _copyPoseToClipboard,
                    child: const Text("Copy Pose to Clipboard"),
                  ),
                ),
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
