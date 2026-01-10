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
  // Mapping of bone IDs to their StickmanNode objects
  late Map<String, StickmanNode> _nodes;

  // View Parameters (Replaces InteractiveViewer for 3D)
  double _rotationX = 0.0; // Pitch
  double _rotationY = 0.0; // Yaw (Turntable)
  double _zoom = 2.0;      // Default Larger Zoom
  Offset _pan = Offset.zero;

  // Selection State
  String? _selectedNodeId;

  @override
  void initState() {
    super.initState();
    _refreshNodeCache();

    // Set to ManualMotionStrategy
    widget.controller.setStrategy(ManualMotionStrategy());
  }

  void _refreshNodeCache() {
    // Rebuild local map from root traversal to ensure we have all current nodes
    final allNodes = <StickmanNode>[];
    void traverse(StickmanNode n) {
      allNodes.add(n);
      for(var c in n.children) traverse(c);
    }
    traverse(widget.controller.skeleton.root);
    _nodes = { for(var n in allNodes) n.id : n };
  }

  // Coordinate Mapping
  // Must match StickmanPainter.project logic
  Offset _toScreen(v.Vector3 vec, Size size) {
    return StickmanPainter.project(
      vec * widget.controller.scale,
      size,
      _rotationX,
      _rotationY,
      _zoom,
      _pan
    );
  }

  void _updateBonePosition(String nodeId, Offset delta) {
    if (!_nodes.containsKey(nodeId)) return;

    final node = _nodes[nodeId]!;
    final modelScale = widget.controller.scale;
    if (modelScale == 0) return;

    // Apply Inverse Rotation to Delta
    // We are dragging in Screen Space (DX, DY).
    // We want World Space delta (WX, WY, WZ).
    // The View Rotation was:
    // X' = X cosY - Z sinY
    // Z' = X sinY + Z cosY
    // Y' = Y
    // (Then pitch X...)

    // This inverse is complex because we project 3D to 2D.
    // Movement in Screen X corresponds to movement along the View Right vector.
    // Movement in Screen Y corresponds to movement along the View Up vector.

    // View Right Vector in World Space:
    // Start with (1,0,0). Rotate Y(yaw) -> (cosY, 0, sinY). Rotate X(pitch) -> (cosY, 0, sinY) if Pitch is 0?
    // Let's assume Pitch is small or handled simply.
    // Ideally, we invert the rotation matrix.

    // Simple approach:
    // Rotate the delta vector (dx, dy, 0) by the Inverse View Rotation.
    // Inverse Orbit Rotation:
    // Un-pitch (X), then Un-yaw (Y).

    // Let's construct a simple rotation logic inverse.
    // Screen X corresponds to Camera Right.
    // Screen Y corresponds to Camera Up.

    // Camera Basis vectors in World Space:
    // Right = (cos(-rotY), 0, -sin(-rotY)) = (cosY, 0, sinY) ? (Check signs)
    // Up = ...

    // Let's use VectorMath Matrix.
    final rotMatrix = v.Matrix4.identity()
      ..rotateX(_rotationX)
      ..rotateY(_rotationY);

    // The view transform rotates World to Camera.
    // So Camera to World is the Inverse.
    final invMatrix = v.Matrix4.inverted(rotMatrix);

    // Screen Delta as a vector on the View Plane
    final screenDelta = v.Vector3(delta.dx, delta.dy, 0);

    // Transform by Inverse
    final worldDelta = invMatrix.transform3(screenDelta);

    // Scale adjustment
    final scaleFactor = modelScale * _zoom;

    node.position.x += worldDelta.x / scaleFactor;
    node.position.y += worldDelta.y / scaleFactor;
    node.position.z += worldDelta.z / scaleFactor;
  }

  // Node Operations
  void _addNodeToSelected() {
    if (_selectedNodeId == null || !_nodes.containsKey(_selectedNodeId)) return;

    final parent = _nodes[_selectedNodeId]!;
    final newNodeId = 'node_${DateTime.now().millisecondsSinceEpoch}';
    // Offset relative to parent in screen space? No, just world offset.
    final offset = v.Vector3(5, 5, 0);
    final newNode = StickmanNode(newNodeId, parent.position + offset);

    setState(() {
      parent.children.add(newNode);
      _refreshNodeCache();
      _selectedNodeId = newNodeId;
    });
  }

  void _removeSelectedNode() {
     if (_selectedNodeId == null || _selectedNodeId == 'hip') return;

     StickmanNode? parent;
     for (var node in _nodes.values) {
       if (node.children.any((c) => c.id == _selectedNodeId)) {
         parent = node;
         break;
       }
     }

     if (parent != null) {
       setState(() {
         parent!.children.removeWhere((c) => c.id == _selectedNodeId);
         _selectedNodeId = null;
         _refreshNodeCache();
       });
     }
  }

  @override
  Widget build(BuildContext context) {
    _refreshNodeCache(); // Ensure sync before build

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);

        return Scaffold( // Use Scaffold for background color
          backgroundColor: Colors.grey[900],
          body: Stack(
            children: [
              // Layer 1: Gesture Detector & Painter
              GestureDetector(
                behavior: HitTestBehavior.opaque, // Catch all touches in background
                onScaleStart: (details) {
                  // No-op, just start
                },
                onScaleUpdate: (details) {
                  setState(() {
                    if (details.pointerCount == 1) {
                      // One finger: Rotate
                      // Sensitivity
                      _rotationY -= details.focalPointDelta.dx * 0.01;
                      _rotationX += details.focalPointDelta.dy * 0.01;
                      // Clamp Pitch to avoid flipping?
                      // _rotationX = _rotationX.clamp(-1.5, 1.5);
                    } else {
                      // Two fingers: Zoom (Scale) & Pan?
                      // details.scale is relative to start of gesture.
                      // We need relative to previous frame?
                      // onScaleUpdate provides scale since start.
                      // This is tricky without storing previousScale.
                      // Let's use horizontalDrag/verticalDrag for Rotate if pointer==1?
                      // onScaleUpdate covers everything.

                      // Simple zoom logic:
                      // We can just use the scale delta if we track it, OR just map scale directly.
                      // But details.scale resets to 1.0 each gesture start? No, it accumulates.

                      // Actually, let's just implement Zoom via scale delta:
                      // But details.scale is "scale of this gesture".
                      // We need `_zoom *= details.scaleDelta` equivalent.
                      // `details.scale` is total scale since start.
                      // We can assume small changes per frame? No.

                      // Standard pattern:
                      // Store `_baseZoom` on ScaleStart.
                      // `_zoom = _baseZoom * details.scale`.
                    }
                  });
                },
                // Let's try simpler separate callbacks
                onPanUpdate: (details) {
                   // Single finger pan -> Rotate
                   setState(() {
                      _rotationY -= details.delta.dx * 0.01;
                      _rotationX += details.delta.dy * 0.01;
                   });
                },
                child: CustomPaint(
                   painter: StickmanPainter(
                     controller: widget.controller,
                     viewRotationX: _rotationX,
                     viewRotationY: _rotationY,
                     viewZoom: _zoom,
                     viewPan: _pan,
                     color: Colors.white,
                   ),
                   size: Size.infinite,
                ),
              ),

              // Zoom Slider (Alternative to Pinch for simplicity/robustness)
              Positioned(
                left: 20,
                bottom: 100,
                child: RotatedBox(
                  quarterTurns: 3,
                  child: SizedBox(
                    width: 200,
                    child: Slider(
                      value: _zoom,
                      min: 0.5,
                      max: 5.0,
                      onChanged: (v) => setState(() => _zoom = v),
                      label: "Zoom",
                    ),
                  ),
                ),
              ),

              // Layer 2: Handles
              ..._nodes.values.map((node) {
                final screenPos = _toScreen(node.position, size);
                final isSelected = node.id == _selectedNodeId;

                return Positioned(
                  left: screenPos.dx - 10,
                  top: screenPos.dy - 10,
                  child: GestureDetector(
                    onPanStart: (_) {
                       setState(() {
                         _selectedNodeId = node.id;
                       });
                    },
                    onPanUpdate: (details) {
                      setState(() {
                        _updateBonePosition(node.id, details.delta);
                      });
                    },
                    onTap: () {
                      setState(() {
                        _selectedNodeId = node.id;
                      });
                    },
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.red : Colors.blue.withOpacity(0.5),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: isSelected ? 3 : 2
                        ),
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                         if (_selectedNodeId != null) ...[
                            FloatingActionButton.small(
                              onPressed: _addNodeToSelected,
                              child: const Icon(Icons.add),
                              tooltip: "Add Child Node",
                            ),
                            const SizedBox(height: 8),
                            if (_selectedNodeId != 'hip')
                            FloatingActionButton.small(
                              onPressed: _removeSelectedNode,
                              backgroundColor: Colors.red,
                              child: const Icon(Icons.delete),
                              tooltip: "Remove Node",
                            ),
                            const SizedBox(height: 16),
                         ],
                         ElevatedButton(
                          onPressed: _copyPoseToClipboard,
                          child: const Text("Copy Pose"),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _copyPoseToClipboard() {
    final skel = widget.controller.skeleton;
    final buffer = StringBuffer();
    String format(v.Vector3 v) => "${v.x.toStringAsFixed(1)}, ${v.y.toStringAsFixed(1)}, ${v.z.toStringAsFixed(1)}";
    for(var name in ['hip','neck','lShoulder','rShoulder','lHip','rHip','lKnee','rKnee','lFoot','rFoot','lElbow','rElbow','lHand','rHand']) {
       if (_nodes.containsKey(name)) {
         buffer.writeln("..$name.setValues(${format(_nodes[name]!.position)})");
       }
    }
    buffer.writeln("\n// Full Tree JSON:");
    buffer.writeln(skel.toJson().toString());

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Pose & JSON copied to clipboard!")),
    );
  }
}
