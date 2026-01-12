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
    _regenerateDefaultClips();
  }

  // --- FIX: REGENERATE DEFAULTS ---
  void _regenerateDefaultClips() {
    final style = widget.controller.skeleton;

    void updateOrAdd(String name, StickmanClip Function() gen) {
      final index = _projectClips.indexWhere((c) => c.name == name);
      final newClip = gen();
      if (index != -1) {
        // Replace existing default clip
        _projectClips[index] = newClip;
      } else {
        // Add new if not exists
        _projectClips.add(newClip);
      }
    }

    updateOrAdd("Run", () => StickmanGenerator.generateRun(style));
    updateOrAdd("Jump", () => StickmanGenerator.generateJump(style));
    updateOrAdd("Kick", () => StickmanGenerator.generateKick(style));
  }

  // --- NEW: RESET FUNCTION ---
  void _resetPoseAndDefaults() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Reset Pose?"),
        content: Text("This will reset the skeleton to T-Pose and regenerate the default Run/Jump/Kick animations. Custom animations will be kept."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                // 1. Reset Skeleton to default
                // StickmanSkeleton is final in Controller, so we lerp to a fresh one instanty
                widget.controller.skeleton.lerp(StickmanSkeleton(), 1.0);

                // 2. Regenerate Defaults based on this new pose
                _regenerateDefaultClips();

                // 3. Clear selection
                _selectedNodeId = null;

                // 4. Force update
                if (widget.controller.activeClip != null) {
                   // If we are currently playing a default clip, reload it
                   final activeName = widget.controller.activeClip!.name;
                   final reloaded = _projectClips.firstWhere(
                     (c) => c.name == activeName,
                     orElse: () => _projectClips.first
                   );
                   widget.controller.activeClip = reloaded;
                }
              });
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Pose & Defaults Reset!")));
            },
            child: Text("Reset")
          ),
        ],
      )
    );
  }

  void _switchMode(EditorMode mode) {
    if (mode == EditorMode.animate) {
      _regenerateDefaultClips();
      _syncProjectStyles();
      if (widget.controller.activeClip == null && _projectClips.isNotEmpty) {
        _activateClip(_projectClips.first);
      }
    }
    setState(() {
      widget.controller.setMode(mode);
    });
  }

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
    _syncProjectStyles();
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
    widget.controller.lastModifiedBone = nodeId;

    final modelScale = widget.controller.scale;
    if (modelScale == 0) return;
    final scaleFactor = modelScale * _zoom;

    // 1. Calculate the requested delta in World Space
    v.Vector3 worldDelta = v.Vector3.zero();

    if (_cameraView == CameraView.free) {
      final rotMatrix = v.Matrix4.identity()
        ..rotateX(_rotationX)
        ..rotateY(_rotationY);

      if (_axisMode == AxisMode.none) {
        final invMatrix = v.Matrix4.inverted(rotMatrix);
        final deltaView = v.Vector3(screenDelta.dx, screenDelta.dy, 0);
        final worldMove = invMatrix.transform3(deltaView);
        worldMove.scale(1.0 / scaleFactor);
        worldDelta = worldMove;
      } else {
        worldDelta = _calculateAxisConstrainedDelta(screenDelta, scaleFactor, rotMatrix);
      }
    } else {
      double dx = screenDelta.dx / scaleFactor;
      double dy = screenDelta.dy / scaleFactor;

      if (_axisMode == AxisMode.none) {
        if (_cameraView == CameraView.front) worldDelta.setValues(dx, dy, 0);
        else if (_cameraView == CameraView.side) worldDelta.setValues(0, dy, dx);
        else if (_cameraView == CameraView.top) worldDelta.setValues(dx, 0, dy);
      } else {
        if (_cameraView == CameraView.front) {
           if (_axisMode == AxisMode.x) worldDelta.x = dx;
           if (_axisMode == AxisMode.y) worldDelta.y = dy;
        } else if (_cameraView == CameraView.side) {
           if (_axisMode == AxisMode.z) worldDelta.z = dx;
           if (_axisMode == AxisMode.y) worldDelta.y = dy;
        } else if (_cameraView == CameraView.top) {
           if (_axisMode == AxisMode.x) worldDelta.x = dx;
           if (_axisMode == AxisMode.z) worldDelta.z = dy;
        }
      }
    }

    _applySmartMove(nodeId, worldDelta);

    if (widget.controller.mode == EditorMode.animate) {
      widget.controller.saveCurrentPoseToFrame();
    }
  }

  v.Vector3 _calculateAxisConstrainedDelta(Offset screenDelta, double scaleFactor, v.Matrix4 rotMatrix) {
      v.Vector3 axisDir;
      if (_axisMode == AxisMode.x) axisDir = v.Vector3(1, 0, 0);
      else if (_axisMode == AxisMode.y) axisDir = v.Vector3(0, 1, 0);
      else axisDir = v.Vector3(0, 0, 1);

      final viewAxis = rotMatrix.transform3(axisDir.clone());
      final screenAxisDir = Offset(viewAxis.x, viewAxis.y);
      double screenMag = screenAxisDir.distance;
      if (screenMag < 0.001) return v.Vector3.zero();

      final screenAxisUnit = screenAxisDir / screenMag;
      double projection = screenDelta.dx * screenAxisUnit.dx + screenDelta.dy * screenAxisUnit.dy;
      double worldMoveAmount = projection / (scaleFactor * screenMag);
      return axisDir * worldMoveAmount;
  }

  void _applySmartMove(String nodeId, v.Vector3 delta) {
    if (delta.length == 0) return;

    bool isEndEffector = ['lHand', 'rHand', 'lFoot', 'rFoot'].contains(nodeId);
    bool isMidJoint = ['lElbow', 'rElbow', 'lKnee', 'rKnee'].contains(nodeId);
    bool isRoot = nodeId == 'hip';
    bool isNeck = nodeId == 'neck';

    if (isRoot) {
      _recursiveMove(_nodes['hip']!, delta);
    } else if (isNeck) {
      _applyConstrainedFKMove(nodeId, 'hip', delta);
    } else if (isMidJoint) {
      String parentId = _getParentId(nodeId);
      if (parentId.isNotEmpty) {
        _applyConstrainedFKMove(nodeId, parentId, delta);
      }
    } else if (isEndEffector) {
      _applyIKMove(nodeId, delta);
    } else {
      if (_nodes.containsKey(nodeId)) {
        _recursiveMove(_nodes[nodeId]!, delta);
      }
    }
  }

  String _getParentId(String nodeId) {
    if (nodeId == 'lElbow' || nodeId == 'rElbow') return 'neck';
    if (nodeId == 'lKnee' || nodeId == 'rKnee') return 'hip';
    if (nodeId == 'lHand') return 'lElbow';
    if (nodeId == 'rHand') return 'rElbow';
    if (nodeId == 'lFoot') return 'lKnee';
    if (nodeId == 'rFoot') return 'rKnee';
    if (nodeId == 'neck') return 'hip';
    if (nodeId == 'head') return 'neck';
    return '';
  }

  void _recursiveMove(StickmanNode node, v.Vector3 delta) {
    node.position.add(delta);
    for (var child in node.children) {
      _recursiveMove(child, delta);
    }
  }

  void _applyConstrainedFKMove(String nodeId, String parentId, v.Vector3 requestedDelta) {
    final node = _nodes[nodeId]!;
    final parent = _nodes[parentId]!;
    v.Vector3 oldPos = node.position.clone();
    v.Vector3 targetPos = oldPos + requestedDelta;

    double currentLength = oldPos.distanceTo(parent.position);
    v.Vector3 dir = targetPos - parent.position;
    double newLen = dir.length;

    v.Vector3 constrainedPos;
    if (newLen > 0.001) {
      dir.normalize();
      constrainedPos = parent.position + (dir * currentLength);
    } else {
      constrainedPos = oldPos;
    }

    v.Vector3 effectiveDelta = constrainedPos - oldPos;
    _recursiveMove(node, effectiveDelta);
  }

  void _applyIKMove(String effectorId, v.Vector3 delta) {
    final effector = _nodes[effectorId]!;
    String jointId = _getParentId(effectorId);
    if (jointId.isEmpty) return;
    final joint = _nodes[jointId]!;

    String rootId = _getParentId(jointId);
    if (rootId.isEmpty) return;
    final root = _nodes[rootId]!;

    double lenUpper = joint.position.distanceTo(root.position);
    double lenLower = effector.position.distanceTo(joint.position);

    v.Vector3 targetEffectorPos = effector.position + delta;

    _solveTwoBoneIK(root.position, joint, effector, targetEffectorPos, lenUpper, lenLower);
  }

  void _solveTwoBoneIK(v.Vector3 rootPos, StickmanNode jointNode, StickmanNode effectorNode, v.Vector3 targetPos, double len1, double len2) {
    v.Vector3 direction = targetPos - rootPos;
    double distance = direction.length;

    // 1. Clamp Target
    if (distance > (len1 + len2)) {
      direction.normalize();
      targetPos = rootPos + (direction * (len1 + len2));
      distance = len1 + len2;
    }

    // 2. Solve Angle
    double cosAlpha = (len1 * len1 + distance * distance - len2 * len2) / (2 * len1 * distance);
    if (cosAlpha > 1.0) cosAlpha = 1.0;
    if (cosAlpha < -1.0) cosAlpha = -1.0;
    double alpha = acos(cosAlpha);

    // 3. Determine Rotation Axis (Bend Normal)
    v.Vector3 armAxis = direction.normalized();
    v.Vector3 bendNormal = v.Vector3.zero();

    // STRICT CONSTRAINTS (Revived)
    v.Vector3? pole;
    // Check ID to determine pole
    if (jointNode.id.contains('Knee')) {
       pole = v.Vector3(0, 0, 1); // Knee Forward (+Z)
    } else if (jointNode.id.contains('Elbow')) {
       pole = v.Vector3(0, 0, -1); // Elbow Backward (-Z)
    }

    if (pole != null) {
       bendNormal = armAxis.cross(pole);
       // Handle collinear case
       if (bendNormal.length < 0.001) {
          bendNormal = armAxis.cross(v.Vector3(1, 0, 0));
       }
    } else {
       // Fallback for non-constrained limbs: Use current state
       v.Vector3 currentLimbVector = jointNode.position - rootPos;
       bendNormal = armAxis.cross(currentLimbVector);
    }

    bendNormal.normalize();
    if (bendNormal.length == 0) bendNormal = v.Vector3(1, 0, 0); // Safety

    // 4. Calculate New Joint
    v.Quaternion q = v.Quaternion.axisAngle(bendNormal, alpha);
    v.Vector3 upperArmVec = q.rotate(armAxis) * len1;
    v.Vector3 newJointPos = rootPos + upperArmVec;

    // 5. Update
    jointNode.position.setFrom(newJointPos);
    effectorNode.position.setFrom(targetPos);
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
                                          await StickmanPersistence.saveProject(
                                            _projectClips,
                                            widget.controller.skeleton.headRadius,
                                            widget.controller.skeleton.strokeWidth
                                          );
                                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("All Animations Saved!")));
                                        },
                                      ),
                                      const SizedBox(width: 10),
                                      ElevatedButton.icon(
                                        icon: Icon(Icons.folder_open, size: 16),
                                        label: Text("Load Project"),
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                                        onPressed: () async {
                                          final projectData = await StickmanPersistence.loadProject();
                                          if (projectData != null && projectData.clips.isNotEmpty) {
                                            setState(() {
                                              _projectClips = projectData.clips;
                                              widget.controller.skeleton.headRadius = projectData.headRadius;
                                              widget.controller.skeleton.strokeWidth = projectData.strokeWidth;
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
                              ElevatedButton(onPressed: _saveObjToFile, child: const Text("OBJ")),
                              const SizedBox(width: 16),
                              ElevatedButton(
                                onPressed: _resetPoseAndDefaults,
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                child: const Text("Reset All"),
                              ),
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

  // --- RESTORED HELPER METHODS ---

  Widget _viewButton(String label, CameraView view) {
    bool selected = _cameraView == view;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: InkWell(
        onTap: () => setState(() => _cameraView = view),
        child: Container(
          width: 50, padding: const EdgeInsets.symmetric(vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: selected ? Colors.blueAccent : Colors.transparent, borderRadius: BorderRadius.circular(4)),
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
          width: 40, padding: const EdgeInsets.symmetric(vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: selected ? Colors.amber : Colors.transparent, borderRadius: BorderRadius.circular(4)),
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

  Future<void> _saveObjToFile() async {
    final obj = StickmanExporter.generateObjString(widget.controller.skeleton);
    if (Platform.isAndroid || Platform.isIOS) {
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/stickman.obj');
      await file.writeAsString(obj);
      await Share.shareXFiles([XFile(file.path)], text: 'Stickman 3D Model');
    } else {
      String? outputFile = await FilePicker.platform.saveFile(dialogTitle: 'Save OBJ', fileName: 'stickman.obj', type: FileType.any);
      if (outputFile != null) {
        await File(outputFile).writeAsString(obj);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("OBJ Saved!")));
      }
    }
  }

  void _applyBoneToAll() {
    widget.controller.propagatePoseToAllFrames();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Applied ${widget.controller.lastModifiedBone} to all frames")));
  }

  Future<void> _exportZip() async {
    if (widget.controller.activeClip == null) return;
    final bytes = await StickmanExporter.exportClipToZip(widget.controller.activeClip!);
    if (Platform.isAndroid || Platform.isIOS) {
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/animation.zip');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: 'Stickman Animation ZIP');
    } else {
      String? outputFile = await FilePicker.platform.saveFile(dialogTitle: 'Save ZIP', fileName: 'animation.zip', type: FileType.any);
      if (outputFile != null) {
        await File(outputFile).writeAsBytes(bytes);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("ZIP Saved!")));
      }
    }
  }
}