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
import 'stickman_persistence.dart';
import 'package:file_picker/file_picker.dart';

class StickmanPoseEditor extends StatefulWidget {
  final StickmanController controller;

  const StickmanPoseEditor({Key? key, required this.controller}) : super(key: key);

  @override
  State<StickmanPoseEditor> createState() => _StickmanPoseEditorState();
}

class _StickmanPoseEditorState extends State<StickmanPoseEditor> {
  late Map<String, StickmanNode> _nodes;

  // --- PROJECT STATE ---
  List<StickmanClip> _projectClips = [];

  // View Parameters
  CameraView _cameraView = CameraView.free;
  double _rotationX = 0.0;
  double _rotationY = 0.0;
  double _zoom = 2.0;
  Offset _pan = Offset.zero;
  double _cameraHeight = 0.0;

  String? _selectedNodeId;
  AxisMode _axisMode = AxisMode.none;

  @override
  void initState() {
    super.initState();
    _refreshNodeCache();
    widget.controller.setStrategy(ManualMotionStrategy());
    // We do NOT generate defaults here anymore.
    // We wait until the first mode switch or we just initialize empty.
    // If we init here, they won't have the user's custom pose if they edit it later.
    // But to show something on first load, we can init defaults.
    _regenerateDefaultClips();
  }

  // --- FIX: REGENERATE DEFAULTS ---
  // This ensures that "Run", "Jump", "Kick" always use the user's current
  // limb lengths (Pose) when they enter Animate mode.
  void _regenerateDefaultClips() {
    final style = widget.controller.skeleton;

    void updateClip(String name, StickmanClip Function() gen) {
      final index = _projectClips.indexWhere((c) => c.name == name);
      final newClip = gen();
      if (index != -1) {
        _projectClips[index] = newClip;
      } else {
        _projectClips.add(newClip);
      }
    }

    updateClip("Run", () => StickmanGenerator.generateRun(style));
    updateClip("Jump", () => StickmanGenerator.generateJump(style));
    updateClip("Kick", () => StickmanGenerator.generateKick(style));
  }

  void _switchMode(EditorMode mode) {
    if (mode == EditorMode.animate) {
      // FIX: FORCE REGENERATE DEFAULTS from current Pose
      // This applies the limb length/position changes to the animation.
      _regenerateDefaultClips();

      // Also Sync style (Head radius/stroke)
      _syncProjectStyles();

      if (widget.controller.activeClip == null && _projectClips.isNotEmpty) {
        _activateClip(_projectClips.first);
      }
    }
    setState(() {
      widget.controller.setMode(mode);
    });
  }

  // Sync style settings (Line/Head) to the animation frames
  void _syncProjectStyles() {
    final currentStyle = widget.controller.skeleton;
    for (var clip in _projectClips) {
      for (var frame in clip.keyframes) {
        frame.pose.headRadius = currentStyle.headRadius;
        frame.pose.strokeWidth = currentStyle.strokeWidth;
      }
    }
  }

  void _activateClip(StickmanClip clip) {
    _syncProjectStyles(); // Ensure this clip is fresh style-wise
    setState(() {
      widget.controller.activeClip = clip;
      widget.controller.currentFrameIndex = 0.0;
      widget.controller.isPlaying = true;
    });
  }

  void _promptAddAnimation() {
    final textController = TextEditingController(text: "New Animation");
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Create Animation"),
        content: TextField(
          controller: textController,
          decoration: InputDecoration(hintText: "Enter Name"),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              final name = textController.text.trim();
              if (name.isNotEmpty) {
                // Generate using CURRENT RIG
                final newClip = StickmanGenerator.generateEmpty(widget.controller.skeleton);
                final finalClip = StickmanClip(
                  name: name,
                  keyframes: newClip.keyframes,
                  fps: 30,
                  isLooping: true
                );

                setState(() {
                  _projectClips.add(finalClip);
                });
                _activateClip(finalClip);
                Navigator.pop(context);
              }
            },
            child: Text("Create"),
          ),
        ],
      ),
    );
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
    widget.controller.lastModifiedBone = node.id;

    final modelScale = widget.controller.scale;
    if (modelScale == 0) return;
    final scaleFactor = modelScale * _zoom;

    void applyMove(v.Vector3 delta) {
      node.position.add(delta);
      if (widget.controller.mode == EditorMode.animate) {
        widget.controller.saveCurrentPoseToFrame();
      }
    }

    if (_cameraView == CameraView.free) {
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
    final styleLabel = TextStyle(color: Colors.white70, fontSize: 10);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);

        return Scaffold(
          backgroundColor: Colors.grey[900],
          body: Stack(
            children: [
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

              ..._nodes.values.map((node) {
                final screenPos = _toScreen(node.position, size);
                final isSelected = node.id == _selectedNodeId;
                return Positioned(
                  left: screenPos.dx - 10,
                  top: screenPos.dy - 10,
                  child: GestureDetector(
                    onPanStart: (_) => setState(() => _selectedNodeId = node.id),
                    onPanUpdate: (details) => setState(() => _updateBonePosition(node.id, details.delta)),
                    onTap: () => setState(() => _selectedNodeId = node.id),
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.red : Colors.blue.withOpacity(0.5),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: isSelected ? 3 : 2),
                      ),
                    ),
                  ),
                );
              }).toList(),

              SafeArea(
                child: Stack(
                  children: [
                    Positioned(
                      top: 10, left: 0, right: 0,
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

                    Positioned(
                      top: 60, left: 10, bottom: 120, width: 80,
                      child: SingleChildScrollView(
                        child: Column(
                           crossAxisAlignment: CrossAxisAlignment.start,
                           children: [
                             Container(
                               padding: const EdgeInsets.all(4),
                               decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
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
                             Text("Height", style: styleLabel),
                             SizedBox(
                               height: 150,
                               child: RotatedBox(
                                 quarterTurns: 3,
                                 child: Slider(
                                   value: _cameraHeight, min: -200, max: 200,
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
                                   value: _zoom, min: 0.5, max: 10.0,
                                   onChanged: (v) => setState(() => _zoom = v),
                                 ),
                               ),
                             ),
                           ],
                        ),
                      ),
                    ),

                    Positioned(
                      top: 60, right: 10, bottom: 120, width: 80,
                      child: SingleChildScrollView(
                        child: Column(
                           crossAxisAlignment: CrossAxisAlignment.end,
                           children: [
                             Container(
                               padding: const EdgeInsets.all(4),
                               decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
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
                             Text("Head", style: styleLabel),
                             SizedBox(
                               height: 150,
                               child: RotatedBox(
                                 quarterTurns: 3,
                                 child: Slider(
                                   value: widget.controller.skeleton.headRadius, min: 2.0, max: 15.0,
                                   onChanged: (v) => setState(() => widget.controller.skeleton.headRadius = v),
                                 ),
                               ),
                             ),
                             const SizedBox(height: 20),
                             Text("Line", style: styleLabel),
                             SizedBox(
                               height: 150,
                               child: RotatedBox(
                                 quarterTurns: 3,
                                 child: Slider(
                                   value: widget.controller.skeleton.strokeWidth, min: 1.0, max: 10.0,
                                   onChanged: (v) => setState(() => widget.controller.skeleton.strokeWidth = v),
                                 ),
                               ),
                             ),
                           ],
                        ),
                      ),
                    ),

                    Positioned(
                      bottom: 10, left: 0, right: 0,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.controller.mode == EditorMode.animate)
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              color: Colors.black54,
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      ElevatedButton.icon(
                                        icon: Icon(Icons.save, size: 16),
                                        label: Text("Save Project"),
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                                        onPressed: () async {
                                          await StickmanPersistence.saveProject(_projectClips);
                                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("All Animations Saved!")));
                                        },
                                      ),
                                      const SizedBox(width: 10),
                                      ElevatedButton.icon(
                                        icon: Icon(Icons.folder_open, size: 16),
                                        label: Text("Load Project"),
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                                        onPressed: () async {
                                          final clips = await StickmanPersistence.loadProject();
                                          if (clips != null && clips.isNotEmpty) {
                                            setState(() {
                                              _projectClips = clips;
                                            });
                                            _activateClip(_projectClips.first);
                                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Project Loaded!")));
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 5),
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        ..._projectClips.map((clip) => _clipButton(clip.name, () => _activateClip(clip))),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 4),
                                          child: IconButton(
                                            icon: Icon(Icons.add_circle, color: Colors.greenAccent),
                                            onPressed: _promptAddAnimation,
                                            tooltip: "Create New Animation",
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          widget.controller.isPlaying ? Icons.pause : Icons.play_arrow,
                                          color: Colors.white, size: 28
                                        ),
                                        onPressed: _togglePlayback,
                                      ),
                                      if (widget.controller.lastModifiedBone != null)
                                        TextButton(
                                          onPressed: _applyBoneToAll,
                                          style: TextButton.styleFrom(
                                            foregroundColor: Colors.amber,
                                            padding: EdgeInsets.symmetric(horizontal: 8),
                                          ),
                                          child: Text("All", style: TextStyle(fontWeight: FontWeight.bold)),
                                        ),
                                      Expanded(
                                        child: Slider(
                                          value: widget.controller.currentFrameIndex.clamp(0.0, (widget.controller.activeClip?.frameCount.toDouble() ?? 1) - 0.01),
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
                                      Text("${widget.controller.currentFrameIndex.floor()}", style: TextStyle(color: Colors.white)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          SizedBox(height: 10),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ElevatedButton(onPressed: _copyPoseToClipboard, child: const Text("Copy")),
                              const SizedBox(width: 16),
                              ElevatedButton(onPressed: _saveObjToFile, child: const Text("OBJ")),
                              if (widget.controller.mode == EditorMode.animate && widget.controller.activeClip != null) ...[
                                const SizedBox(width: 16),
                                ElevatedButton(
                                  onPressed: _exportZip,
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
                                  child: const Text("ZIP"),
                                ),
                              ],
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
