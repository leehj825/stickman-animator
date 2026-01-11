import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' as v;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'stickman_skeleton.dart';
import 'stickman_animator.dart';
import 'stickman_painter.dart';
import 'stickman_exporter.dart';
import 'stickman_animation.dart';
import 'stickman_generator.dart';

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

  void _switchMode(EditorMode mode) {
    setState(() {
      widget.controller.setMode(mode);
    });
  }

  void _loadClip(StickmanClip clip) {
    setState(() {
      widget.controller.activeClip = clip;
      widget.controller.currentFrameIndex = 0.0;
      widget.controller.isPlaying = true;
    });
  }

  void _togglePlayback() {
    setState(() {
      widget.controller.isPlaying = !widget.controller.isPlaying;
    });
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

    // Helper to apply changes
    void applyMove(v.Vector3 delta) {
      node.position.add(delta);
      // If in Animation Mode, save changes to the current frame
      if (widget.controller.mode == EditorMode.animate) {
        widget.controller.saveCurrentPoseToFrame();
      }
    }

    // Inverse Logic depends on CameraView
    if (_cameraView == CameraView.free) {
      // 3D Inverse with Camera-Relative Dragging
      final rotMatrix = v.Matrix4.identity()
        ..rotateX(_rotationX)
        ..rotateY(_rotationY);

      if (_axisMode == AxisMode.none) {
        final invMatrix = v.Matrix4.inverted(rotMatrix);
        final deltaView = v.Vector3(screenDelta.dx, screenDelta.dy, 0);
        final worldMove = invMatrix.transform3(deltaView);
        worldMove.scale(1.0 / scaleFactor);
        applyMove(worldMove);
      } else {
        _applyAxisConstrainedMove(node, screenDelta, scaleFactor, rotMatrix);
        if (widget.controller.mode == EditorMode.animate) {
          widget.controller.saveCurrentPoseToFrame();
        }
      }
    } else {
      // Orthographic Inverse
      double dx = screenDelta.dx / scaleFactor;
      double dy = screenDelta.dy / scaleFactor;
      v.Vector3 delta = v.Vector3.zero();

      if (_axisMode == AxisMode.none) {
        if (_cameraView == CameraView.front) {
          delta.setValues(dx, dy, 0);
        } else if (_cameraView == CameraView.side) {
          delta.setValues(0, dy, dx);
        } else if (_cameraView == CameraView.top) {
          delta.setValues(dx, 0, dy);
        }
      } else {
        // Axis Constrained
        if (_cameraView == CameraView.front) {
           if (_axisMode == AxisMode.x) delta.x = dx;
           if (_axisMode == AxisMode.y) delta.y = dy;
        } else if (_cameraView == CameraView.side) {
           if (_axisMode == AxisMode.z) delta.z = dx;
           if (_axisMode == AxisMode.y) delta.y = dy;
        } else if (_cameraView == CameraView.top) {
           if (_axisMode == AxisMode.x) delta.x = dx;
           if (_axisMode == AxisMode.z) delta.z = dy;
        }
      }
      applyMove(delta);
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
                    // Top Bar: Mode Switcher
                    Positioned(
                      top: 10,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                onTap: () => _switchMode(EditorMode.pose),
                                child: Text("Pose", style: TextStyle(color: widget.controller.mode == EditorMode.pose ? Colors.blue : Colors.white, fontWeight: FontWeight.bold)),
                              ),
                              Container(margin: EdgeInsets.symmetric(horizontal: 8), width: 1, height: 20, color: Colors.white),
                              InkWell(
                                onTap: () => _switchMode(EditorMode.animate),
                                child: Text("Animate", style: TextStyle(color: widget.controller.mode == EditorMode.animate ? Colors.blue : Colors.white, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Left Column (Top Left)
                    Positioned(
                      top: 50, // Moved down for Top Bar
                      left: 10,
                      bottom: 150, // Leave space for bottom bar
                      width: 80,
                      child: Column(
                         crossAxisAlignment: CrossAxisAlignment.start,
                         children: [
                           // Camera View Buttons
                           Container(
                             padding: const EdgeInsets.all(4),
                             decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(8),
                             ),
                             child: Column(
                               children: [
                                 _viewButton("Free", CameraView.free),
                                 _viewButton("View X", CameraView.side),
                                 _viewButton("View Y", CameraView.top),
                                 _viewButton("View Z", CameraView.front),
                               ],
                             ),
                           ),
                           const SizedBox(height: 20),
                           // Camera Height Slider
                           Expanded(
                             child: Column(
                               mainAxisSize: MainAxisSize.min,
                               children: [
                                 Text("Height", style: styleLabel),
                                 SizedBox(
                                   height: 150,
                                   child: RotatedBox(
                                     quarterTurns: 3,
                                     child: Slider(
                                       value: _cameraHeight,
                                       min: -200,
                                       max: 200,
                                       onChanged: (v) => setState(() => _cameraHeight = v),
                                     ),
                                   ),
                                 ),
                                 const SizedBox(height: 20),
                                 Text("Zoom", style: styleLabel),
                                 SizedBox(
                                   height: 150,
                                   child: RotatedBox(
                                     quarterTurns: 3,
                                     child: Slider(
                                       value: _zoom,
                                       min: 0.5,
                                       max: 10.0,
                                       onChanged: (v) => setState(() => _zoom = v),
                                     ),
                                   ),
                                 ),
                               ],
                             ),
                           ),
                         ],
                      ),
                    ),

                    // Right Column (Top Right)
                    Positioned(
                      top: 50, // Moved down for Top Bar
                      right: 10,
                      bottom: 150,
                      width: 80,
                      child: Column(
                         crossAxisAlignment: CrossAxisAlignment.end,
                         children: [
                           // Drag Axis Buttons
                           Container(
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
                           const SizedBox(height: 20),
                           // Head Slider
                           Column(
                             children: [
                               Text("Head", style: styleLabel),
                               SizedBox(
                                 height: 150,
                                 child: RotatedBox(
                                   quarterTurns: 3,
                                   child: Slider(
                                     value: widget.controller.skeleton.headRadius,
                                     min: 2.0,
                                     max: 15.0,
                                     onChanged: (v) => setState(() => widget.controller.skeleton.headRadius = v),
                                   ),
                                 ),
                               ),
                             ],
                           ),
                           const SizedBox(height: 20),
                           // Line Slider
                           Column(
                             children: [
                               Text("Line", style: styleLabel),
                               SizedBox(
                                 height: 150,
                                 child: RotatedBox(
                                   quarterTurns: 3,
                                   child: Slider(
                                     value: widget.controller.skeleton.strokeWidth,
                                     min: 1.0,
                                     max: 10.0,
                                     onChanged: (v) => setState(() => widget.controller.skeleton.strokeWidth = v),
                                   ),
                                 ),
                               ),
                             ],
                           ),
                         ],
                      ),
                    ),

                    // Bottom: Animation Controls (Animate Mode) or Pose Tools
                    Positioned(
                      bottom: 10,
                      left: 0,
                      right: 0,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.controller.mode == EditorMode.animate)
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              color: Colors.black54,
                              child: Column(
                                children: [
                                  // Clip Selector
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        _clipButton("Run", () => _loadClip(AnimationFactory.generateRun())),
                                        _clipButton("Jump", () => _loadClip(AnimationFactory.generateJump())),
                                        _clipButton("Kick", () => _loadClip(AnimationFactory.generateKick())),
                                        _clipButton("+", () {
                                          _loadClip(AnimationFactory.generateEmpty());
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text("New Custom Animation Created (30 Frames)")),
                                            );
                                          }
                                        }),
                                      ],
                                    ),
                                  ),
                                  // Playback Controls
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: Icon(widget.controller.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                                        onPressed: _togglePlayback,
                                      ),
                                      Expanded(
                                        child: Slider(
                                          value: widget.controller.currentFrameIndex,
                                          min: 0,
                                          max: (widget.controller.activeClip?.frameCount.toDouble() ?? 1) - 0.01,
                                          onChanged: (v) {
                                            setState(() {
                                              widget.controller.isPlaying = false;
                                              widget.controller.currentFrameIndex = v;
                                            });
                                          },
                                        ),
                                      ),
                                      Text(
                                        "${widget.controller.currentFrameIndex.floor()}",
                                        style: TextStyle(color: Colors.white),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                          SizedBox(height: 10),

                          // Common Export Row
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ElevatedButton(
                                onPressed: _copyPoseToClipboard,
                                child: const Text("Copy"),
                              ),
                              const SizedBox(width: 16),
                              ElevatedButton(
                                onPressed: _saveObjToFile,
                                child: const Text("OBJ"),
                              ),
                            ],
                          ),
                        ],
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

  Widget _clipButton(String label, VoidCallback onTap) {
    bool isActive = widget.controller.activeClip?.name == label;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isActive ? Colors.blue : Colors.grey[700],
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        ),
        onPressed: onTap,
        child: Text(label, style: TextStyle(fontSize: 12)),
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
      const SnackBar(content: Text("Dart Code copied!")),
    );
  }

  Future<void> _saveObjToFile() async {
    final obj = StickmanExporter.generateObjString(widget.controller.skeleton);

    // Save to temp file
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/stickman.obj');
    await file.writeAsString(obj);

    // Share using share_plus
    // This provides a native save/share dialog
    await Share.shareXFiles([XFile(file.path)], text: 'Stickman 3D Model');

    // Fallback/Confirm
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("OBJ File Ready to Save/Share")),
      );
    }
  }
}
