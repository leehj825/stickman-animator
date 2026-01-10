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

  // View Parameters
  double _rotationX = 0.0; // Pitch
  double _rotationY = 0.0; // Yaw (Turntable)
  double _zoom = 2.0;
  Offset _pan = Offset.zero;

  // Selection State
  String? _selectedNodeId;

  // Axis Mode State
  AxisMode _axisMode = AxisMode.none;

  @override
  void initState() {
    super.initState();
    _refreshNodeCache();
    widget.controller.setStrategy(ManualMotionStrategy());
  }

  void _refreshNodeCache() {
    final allNodes = <StickmanNode>[];
    void traverse(StickmanNode n) {
      allNodes.add(n);
      for(var c in n.children) traverse(c);
    }
    traverse(widget.controller.skeleton.root);
    _nodes = { for(var n in allNodes) n.id : n };
  }

  // Coordinate Mapping
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

  void _updateBonePosition(String nodeId, Offset screenDelta) {
    if (!_nodes.containsKey(nodeId)) return;

    final node = _nodes[nodeId]!;
    final modelScale = widget.controller.scale;
    if (modelScale == 0) return;

    // Scale Factor converting World Units to Screen Pixels
    final scaleFactor = modelScale * _zoom;

    // Inverse View Rotation Matrix (Camera to World)
    final rotMatrix = v.Matrix4.identity()
      ..rotateX(_rotationX)
      ..rotateY(_rotationY);
    final invMatrix = v.Matrix4.inverted(rotMatrix);

    if (_axisMode == AxisMode.none) {
      // Free Move (Screen Plane -> View Plane)
      // Screen X -> View Right -> World Vector
      // Screen Y -> View Up -> World Vector

      final delta3 = v.Vector3(screenDelta.dx, screenDelta.dy, 0);
      final worldDelta = invMatrix.transform3(delta3);

      node.position.x += worldDelta.x / scaleFactor;
      node.position.y += worldDelta.y / scaleFactor;
      node.position.z += worldDelta.z / scaleFactor;

    } else {
      // Axis Constrained Move
      // We want to move along a specific World Axis (e.g. X: 1,0,0)
      // We need to find how much the Screen Drag corresponds to movement along that axis.
      // 1. Project the World Axis onto the Screen Vector.
      // 2. Dot Product Screen Delta with Projected Axis Vector.

      v.Vector3 axisDir;
      if (_axisMode == AxisMode.x) axisDir = v.Vector3(1, 0, 0);
      else if (_axisMode == AxisMode.y) axisDir = v.Vector3(0, 1, 0);
      else axisDir = v.Vector3(0, 0, 1);

      // Transform World Axis to View Space (Camera Relative Axis)
      // We use rotMatrix (World -> Camera)
      // We only rotate the direction, not translate.
      // Actually, rotMatrix is 4x4.
      final viewAxis = rotMatrix.transform3(axisDir.clone()); // Assuming pure rotation matrix

      // Now we have the axis direction in View Space (X=Right, Y=Down, Z=Depth).
      // We project this onto the Screen Plane (X, Y).
      // Since it's orthographic, Screen X = View X, Screen Y = View Y.
      final screenAxisDir = Offset(viewAxis.x, viewAxis.y);

      // If axis is perpendicular to screen (pointing purely in Z), magnitude is 0.
      double screenMag = screenAxisDir.distance;
      if (screenMag < 0.001) return; // Cannot move this axis from this angle

      // Normalize Screen Axis Direction
      final screenAxisUnit = screenAxisDir / screenMag;

      // Project Mouse Delta onto Screen Axis
      double projection = screenDelta.dx * screenAxisUnit.dx + screenDelta.dy * screenAxisUnit.dy;

      // Calculate World Movement Amount
      // projection (pixels) = worldMove * scaleFactor * screenMag (foreshortening)
      // worldMove = projection / (scaleFactor * screenMag)

      double worldMove = projection / (scaleFactor * screenMag);

      // Apply to Node
      node.position.add(axisDir * worldMove);
    }
  }

  void _addNodeToSelected() {
    if (_selectedNodeId == null || !_nodes.containsKey(_selectedNodeId)) return;
    final parent = _nodes[_selectedNodeId]!;
    final newNodeId = 'node_${DateTime.now().millisecondsSinceEpoch}';
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
    _refreshNodeCache();

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);

        return Scaffold(
          backgroundColor: Colors.grey[900],
          body: Stack(
            children: [
              // Layer 1: Gesture & Painter
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) {
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
                     selectedNodeId: _selectedNodeId,
                     axisMode: _axisMode,
                   ),
                   size: Size.infinite,
                ),
              ),

              // Zoom Slider
              Positioned(
                left: 20,
                bottom: 150,
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
                        // Axis Controls
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ToggleButtons(
                            isSelected: [
                              _axisMode == AxisMode.none,
                              _axisMode == AxisMode.x,
                              _axisMode == AxisMode.y,
                              _axisMode == AxisMode.z,
                            ],
                            onPressed: (index) {
                              setState(() {
                                if (index == 0) _axisMode = AxisMode.none;
                                else if (index == 1) _axisMode = AxisMode.x;
                                else if (index == 2) _axisMode = AxisMode.y;
                                else if (index == 3) _axisMode = AxisMode.z;
                              });
                            },
                            color: Colors.white,
                            selectedColor: Colors.amber,
                            fillColor: Colors.white24,
                            children: const [
                              Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text("Free")),
                              Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text("X", style: TextStyle(color: Colors.red))),
                              Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text("Y", style: TextStyle(color: Colors.green))),
                              Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text("Z", style: TextStyle(color: Colors.blue))),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

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
    for(var name in ['hip','neck','head','lShoulder','rShoulder','lHip','rHip','lKnee','rKnee','lFoot','rFoot','lElbow','rElbow','lHand','rHand']) {
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
