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
  CameraView _cameraView = CameraView.free;
  double _rotationX = 0.0; // Pitch
  double _rotationY = 0.0; // Yaw (Turntable)
  double _zoom = 2.0;
  Offset _pan = Offset.zero;
  double _cameraHeight = 0.0; // Vertical Pan

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
      _cameraView,
      _rotationX,
      _rotationY,
      _zoom,
      _pan,
      _cameraHeight
    );
  }

  void _updateBonePosition(String nodeId, Offset screenDelta) {
    if (!_nodes.containsKey(nodeId)) return;

    final node = _nodes[nodeId]!;
    final modelScale = widget.controller.scale;
    if (modelScale == 0) return;

    final scaleFactor = modelScale * _zoom;

    // Inverse Logic depends on CameraView
    if (_cameraView == CameraView.free) {
      // 3D Inverse
      final rotMatrix = v.Matrix4.identity()
        ..rotateX(_rotationX)
        ..rotateY(_rotationY);
      final invMatrix = v.Matrix4.inverted(rotMatrix);

      if (_axisMode == AxisMode.none) {
        final delta3 = v.Vector3(screenDelta.dx, screenDelta.dy, 0);
        final worldDelta = invMatrix.transform3(delta3);
        node.position.x += worldDelta.x / scaleFactor;
        node.position.y += worldDelta.y / scaleFactor;
        node.position.z += worldDelta.z / scaleFactor;
      } else {
        _applyAxisConstrainedMove(node, screenDelta, scaleFactor, rotMatrix);
      }
    } else {
      // Orthographic Inverse
      // Map screen delta (dx, dy) to world axes directly
      double dx = screenDelta.dx / scaleFactor;
      double dy = screenDelta.dy / scaleFactor;

      if (_axisMode == AxisMode.none) {
        if (_cameraView == CameraView.front) {
          // Front: Screen X=World X, Screen Y=World Y. Z unchanged.
          node.position.x += dx;
          node.position.y += dy;
        } else if (_cameraView == CameraView.side) {
          // Side: Screen X=World Z, Screen Y=World Y. X unchanged.
          node.position.z += dx;
          node.position.y += dy;
        } else if (_cameraView == CameraView.top) {
          // Top: Screen X=World X, Screen Y=World Z. Y unchanged.
          node.position.x += dx;
          node.position.z += dy;
        }
      } else {
        // Axis Constrained in Ortho view
        // Just mask the deltas
        if (_cameraView == CameraView.front) {
           if (_axisMode == AxisMode.x) node.position.x += dx;
           if (_axisMode == AxisMode.y) node.position.y += dy;
           // Z cannot be moved in Front view (perpendicular)
        } else if (_cameraView == CameraView.side) {
           if (_axisMode == AxisMode.z) node.position.z += dx;
           if (_axisMode == AxisMode.y) node.position.y += dy;
        } else if (_cameraView == CameraView.top) {
           if (_axisMode == AxisMode.x) node.position.x += dx;
           if (_axisMode == AxisMode.z) node.position.z += dy;
        }
      }
    }
  }

  void _applyAxisConstrainedMove(StickmanNode node, Offset screenDelta, double scaleFactor, v.Matrix4 rotMatrix) {
      v.Vector3 axisDir;
      if (_axisMode == AxisMode.x) axisDir = v.Vector3(1, 0, 0);
      else if (_axisMode == AxisMode.y) axisDir = v.Vector3(0, 1, 0);
      else axisDir = v.Vector3(0, 0, 1);

      final viewAxis = rotMatrix.transform3(axisDir.clone());
      final screenAxisDir = Offset(viewAxis.x, viewAxis.y);
      double screenMag = screenAxisDir.distance;
      if (screenMag < 0.001) return;

      final screenAxisUnit = screenAxisDir / screenMag;
      double projection = screenDelta.dx * screenAxisUnit.dx + screenDelta.dy * screenAxisUnit.dy;
      double worldMove = projection / (scaleFactor * screenMag);
      node.position.add(axisDir * worldMove);
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

    // UI Theme
    final styleLabel = TextStyle(color: Colors.white70, fontSize: 10);

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
                   if (_cameraView == CameraView.free) {
                     setState(() {
                        _rotationY -= details.delta.dx * 0.01;
                        _rotationX += details.delta.dy * 0.01;
                     });
                   }
                },
                child: CustomPaint(
                   painter: StickmanPainter(
                     controller: widget.controller,
                     cameraView: _cameraView,
                     viewRotationX: _rotationX,
                     viewRotationY: _rotationY,
                     viewZoom: _zoom,
                     viewPan: _pan,
                     cameraHeightOffset: _cameraHeight,
                     color: Colors.white,
                     selectedNodeId: _selectedNodeId,
                     axisMode: _axisMode,
                   ),
                   size: Size.infinite,
                ),
              ),

              // Handles
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

              // UI OVERLAYS
              SafeArea(
                child: Stack(
                  children: [
                    // Group B: Camera Views (Top Left)
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                         padding: const EdgeInsets.all(4),
                         decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                         ),
                         child: Column(
                           children: [
                             _viewButton("View X", CameraView.side),
                             _viewButton("View Y", CameraView.top),
                             _viewButton("View Z", CameraView.front),
                             _viewButton("Free", CameraView.free),
                           ],
                         ),
                      ),
                    ),

                    // Group A: Drag Constraints (Top Right)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                         padding: const EdgeInsets.all(4),
                         decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                         ),
                         child: Column(
                           children: [
                             _axisButton("Free", AxisMode.none),
                             _axisButton("X", AxisMode.x, Colors.red),
                             _axisButton("Y", AxisMode.y, Colors.green),
                             _axisButton("Z", AxisMode.z, Colors.blue),
                           ],
                         ),
                      ),
                    ),

                    // Group C: Camera Height (Left Edge Vertical Slider)
                    Positioned(
                      left: 10,
                      top: 200,
                      bottom: 150,
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: SizedBox(
                          width: 200,
                          child: Slider(
                            value: _cameraHeight,
                            min: -200,
                            max: 200,
                            onChanged: (v) => setState(() => _cameraHeight = v),
                            label: "Height",
                          ),
                        ),
                      ),
                    ),

                    // Node Operations (Bottom Right)
                    Positioned(
                      bottom: 20,
                      right: 20,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                           // Style Sliders
                           Container(
                             padding: const EdgeInsets.all(8),
                             margin: const EdgeInsets.only(bottom: 10),
                             decoration: BoxDecoration(
                               color: Colors.black54,
                               borderRadius: BorderRadius.circular(8)
                             ),
                             child: Column(
                               crossAxisAlignment: CrossAxisAlignment.end,
                               children: [
                                 Text("Thickness: ${widget.controller.skeleton.strokeWidth.toStringAsFixed(1)}", style: styleLabel),
                                 SizedBox(
                                   width: 120,
                                   height: 30,
                                   child: Slider(
                                     value: widget.controller.skeleton.strokeWidth,
                                     min: 1.0,
                                     max: 10.0,
                                     onChanged: (v) => setState(() => widget.controller.skeleton.strokeWidth = v),
                                   ),
                                 ),
                                 Text("Head Size: ${widget.controller.skeleton.headRadius.toStringAsFixed(1)}", style: styleLabel),
                                 SizedBox(
                                   width: 120,
                                   height: 30,
                                   child: Slider(
                                     value: widget.controller.skeleton.headRadius,
                                     min: 2.0,
                                     max: 15.0,
                                     onChanged: (v) => setState(() => widget.controller.skeleton.headRadius = v),
                                   ),
                                 ),
                               ],
                             ),
                           ),

                           if (_selectedNodeId != null) ...[
                              FloatingActionButton.small(
                                heroTag: "add",
                                onPressed: _addNodeToSelected,
                                child: const Icon(Icons.add),
                                tooltip: "Add Child Node",
                              ),
                              const SizedBox(height: 8),
                              if (_selectedNodeId != 'hip')
                              FloatingActionButton.small(
                                heroTag: "del",
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

                    // Zoom Slider (Bottom Left)
                    Positioned(
                      left: 50,
                      bottom: 20,
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
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _viewButton(String label, CameraView view) {
    bool selected = _cameraView == view;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: InkWell(
        onTap: () => setState(() => _cameraView = view),
        child: Container(
          width: 50,
          padding: const EdgeInsets.symmetric(vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? Colors.blueAccent : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 10)),
        ),
      ),
    );
  }

  Widget _axisButton(String label, AxisMode mode, [Color color = Colors.white]) {
    bool selected = _axisMode == mode;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: InkWell(
        onTap: () => setState(() => _axisMode = mode),
        child: Container(
          width: 40,
          padding: const EdgeInsets.symmetric(vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? Colors.amber : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(label, style: TextStyle(color: selected ? Colors.black : color, fontSize: 12, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  void _copyPoseToClipboard() {
    final skel = widget.controller.skeleton;
    final buffer = StringBuffer();
    String format(v.Vector3 v) => "${v.x.toStringAsFixed(1)}, ${v.y.toStringAsFixed(1)}, ${v.z.toStringAsFixed(1)}";

    buffer.writeln("static final StickmanSkeleton myPose = StickmanSkeleton()");
    buffer.writeln("  ..headRadius = ${skel.headRadius.toStringAsFixed(1)}");
    buffer.writeln("  ..strokeWidth = ${skel.strokeWidth.toStringAsFixed(1)}");

    for(var name in ['hip','neck','head','lShoulder','rShoulder','lHip','rHip','lKnee','rKnee','lFoot','rFoot','lElbow','rElbow','lHand','rHand']) {
       if (_nodes.containsKey(name)) {
         buffer.writeln("  ..$name.setValues(${format(_nodes[name]!.position)})");
       }
    }
    buffer.writeln("  ;");

    buffer.writeln("\n// Full Tree JSON:");
    buffer.writeln(skel.toJson().toString());

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Pose & JSON copied to clipboard!")),
    );
  }
}
