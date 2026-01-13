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

  // Rotation Slider State
  double _currentRotationValue = 0.0;

  @override
  void initState() {
    super.initState();
    _refreshNodeCache();
    widget.controller.setStrategy(ManualMotionStrategy());
    _regenerateDefaultClips();
  }

  void _regenerateDefaultClips() {
    final style = widget.controller.skeleton;

    void updateOrAdd(String name, StickmanClip Function() gen) {
      final index = _projectClips.indexWhere((c) => c.name == name);
      final newClip = gen();
      if (index != -1) {
        _projectClips[index] = newClip;
      } else {
        _projectClips.add(newClip);
      }
    }

    updateOrAdd("Run", () => StickmanGenerator.generateRun(style));
    updateOrAdd("Jump", () => StickmanGenerator.generateJump(style));
    updateOrAdd("Kick", () => StickmanGenerator.generateKick(style));
  }

  void _resetPoseAndDefaults() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Reset Pose?"),
        content: Text("Reset skeleton to T-Pose and regenerate default animations? Custom animations are kept."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                widget.controller.skeleton.lerp(StickmanSkeleton(), 1.0);
                _regenerateDefaultClips();
                _selectedNodeId = null;
                if (widget.controller.activeClip != null) {
                   final activeName = widget.controller.activeClip!.name;
                   final reloaded = _projectClips.firstWhere(
                     (c) => c.name == activeName,
                     orElse: () => _projectClips.first
                   );
                   widget.controller.activeClip = reloaded;
                }
              });
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Reset Complete")));
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

  void _onNodeSelected(String nodeId) {
    setState(() {
      _selectedNodeId = nodeId;
      _currentRotationValue = _calculateCurrentSwivel(nodeId);
    });
  }

  // --- ROTATION LOGIC ---
  double _calculateCurrentSwivel(String nodeId) {
    if (!_nodes.containsKey(nodeId)) return 0.0;
    final skel = widget.controller.skeleton;

    if (nodeId == 'head') {
      v.Vector3 rel = skel.head! - skel.neck;
      return atan2(rel.x, rel.z);
    }

    String midId = '';
    String rootId = '';
    if (nodeId == 'lHand') { midId = 'lElbow'; rootId = 'neck'; }
    else if (nodeId == 'rHand') { midId = 'rElbow'; rootId = 'neck'; }
    else if (nodeId == 'lFoot') { midId = 'lKnee'; rootId = 'hip'; }
    else if (nodeId == 'rFoot') { midId = 'rKnee'; rootId = 'hip'; }
    else return 0.0;

    v.Vector3 root = skel.getBone(rootId)!;
    v.Vector3 mid = skel.getBone(midId)!;
    v.Vector3 eff = skel.getBone(nodeId)!;

    v.Vector3 axis = (eff - root).normalized();
    if (axis.length == 0) return 0.0;

    v.Vector3 limbVec = mid - root;
    v.Vector3 projMid = limbVec - (axis * limbVec.dot(axis));
    v.Vector3 worldUp = v.Vector3(0, 1, 0);
    if (axis.dot(worldUp).abs() > 0.9) worldUp = v.Vector3(1, 0, 0);
    v.Vector3 ref = (worldUp - (axis * worldUp.dot(axis))).normalized();
    v.Vector3 ortho = axis.cross(ref).normalized();

    double x = projMid.dot(ref);
    double y = projMid.dot(ortho);

    return atan2(y, x);
  }

  void _applyRotation(String nodeId, double angle) {
     final skel = widget.controller.skeleton;
     widget.controller.lastModifiedBone = nodeId;

     if (nodeId == 'head') {
       double dist = skel.neck.distanceTo(skel.head!);
       double x = sin(angle) * dist;
       double z = cos(angle) * dist;
       double yOffset = skel.head!.y - skel.neck.y;
       skel.head!.setFrom(skel.neck + v.Vector3(x, yOffset, z));
     } else {
       String midId = '';
       String rootId = '';
       if (nodeId == 'lHand') { midId = 'lElbow'; rootId = 'neck'; }
       else if (nodeId == 'rHand') { midId = 'rElbow'; rootId = 'neck'; }
       else if (nodeId == 'lFoot') { midId = 'lKnee'; rootId = 'hip'; }
       else if (nodeId == 'rFoot') { midId = 'rKnee'; rootId = 'hip'; }
       else return;

       v.Vector3 root = skel.getBone(rootId)!;
       v.Vector3 mid = skel.getBone(midId)!;
       v.Vector3 eff = skel.getBone(nodeId)!;

       v.Vector3 axis = (eff - root).normalized();
       if (axis.length < 0.001) return;

       v.Vector3 limbVec = mid - root;
       v.Vector3 center = root + (axis * limbVec.dot(axis));
       v.Vector3 radiusVec = mid - center;
       double radiusLen = radiusVec.length;

       v.Vector3 worldUp = v.Vector3(0, 1, 0);
       if (axis.dot(worldUp).abs() > 0.9) worldUp = v.Vector3(1, 0, 0);
       v.Vector3 ref = (worldUp - (axis * worldUp.dot(axis))).normalized();
       v.Vector3 ortho = axis.cross(ref).normalized();

       v.Vector3 newMid = center + (ref * cos(angle) * radiusLen) + (ortho * sin(angle) * radiusLen);
       skel.setBone(midId, newMid);
     }

     if (widget.controller.mode == EditorMode.animate) {
        widget.controller.saveCurrentPoseToFrame();
     }
  }

  void _updateBonePosition(String nodeId, Offset screenDelta) {
    if (!_nodes.containsKey(nodeId)) return;
    widget.controller.lastModifiedBone = nodeId;

    final modelScale = widget.controller.scale;
    if (modelScale == 0) return;
    final scaleFactor = modelScale * _zoom;

    v.Vector3 worldDelta = v.Vector3.zero();

    if (_cameraView == CameraView.free) {
        double cosY = cos(_rotationY);
        double sinY = sin(_rotationY);
        double cosX = cos(_rotationX);
        double sinX = sin(_rotationX);

        v.Vector3 camRight = v.Vector3(cosY, 0, -sinY);
        v.Vector3 camDown = v.Vector3(-sinY * sinX, cosX, -cosY * sinX);

        worldDelta = (camRight * screenDelta.dx + camDown * screenDelta.dy) / scaleFactor;
    } else {
      double dx = screenDelta.dx / scaleFactor;
      double dy = screenDelta.dy / scaleFactor;

      if (_cameraView == CameraView.front) worldDelta.setValues(dx, dy, 0);
      else if (_cameraView == CameraView.side) worldDelta.setValues(0, dy, dx);
      else if (_cameraView == CameraView.top) worldDelta.setValues(dx, 0, dy);
    }

    if (_axisMode == AxisMode.x) worldDelta.setValues(worldDelta.x, 0, 0);
    else if (_axisMode == AxisMode.y) worldDelta.setValues(0, worldDelta.y, 0);
    else if (_axisMode == AxisMode.z) worldDelta.setValues(0, 0, worldDelta.z);

    _applySmartMove(nodeId, worldDelta);

    if (_selectedNodeId == nodeId) {
       _currentRotationValue = _calculateCurrentSwivel(nodeId);
    }

    if (widget.controller.mode == EditorMode.animate) {
      widget.controller.saveCurrentPoseToFrame();
    }
  }

  void _applySmartMove(String nodeId, v.Vector3 delta) {
    if (delta.length == 0) return;
    bool isEndEffector = ['lHand', 'rHand', 'lFoot', 'rFoot'].contains(nodeId);
    bool isMidJoint = ['lElbow', 'rElbow', 'lKnee', 'rKnee'].contains(nodeId);
    bool isRoot = nodeId == 'hip';
    bool isNeck = nodeId == 'neck';

    if (isRoot) _recursiveMove(_nodes['hip']!, delta);
    else if (isNeck) _applyConstrainedFKMove(nodeId, 'hip', delta);
    else if (isMidJoint && _getParentId(nodeId).isNotEmpty) _applyConstrainedFKMove(nodeId, _getParentId(nodeId), delta);
    else if (isEndEffector) _applyIKMove(nodeId, delta);
    else if (_nodes.containsKey(nodeId)) _recursiveMove(_nodes[nodeId]!, delta);
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
    for (var child in node.children) _recursiveMove(child, delta);
  }

  void _applyConstrainedFKMove(String nodeId, String parentId, v.Vector3 requestedDelta) {
    final node = _nodes[nodeId]!;
    final parent = _nodes[parentId]!;
    v.Vector3 oldPos = node.position.clone();
    v.Vector3 targetPos = oldPos + requestedDelta;
    double currentLength = oldPos.distanceTo(parent.position);
    v.Vector3 dir = targetPos - parent.position;
    if (dir.length > 0.001) {
      dir.normalize();
      v.Vector3 constrainedPos = parent.position + (dir * currentLength);
      _recursiveMove(node, constrainedPos - oldPos);
    }
  }

  void _applyIKMove(String effectorId, v.Vector3 delta) {
    final effector = _nodes[effectorId]!;
    String jointId = _getParentId(effectorId);
    String rootId = _getParentId(jointId);
    if (jointId.isEmpty || rootId.isEmpty) return;
    final root = _nodes[rootId]!;
    final joint = _nodes[jointId]!;
    double len1 = joint.position.distanceTo(root.position);
    double len2 = effector.position.distanceTo(joint.position);
    _solveTwoBoneIK(root.position, joint, effector, effector.position + delta, len1, len2);
  }

  void _solveTwoBoneIK(v.Vector3 rootPos, StickmanNode jointNode, StickmanNode effectorNode, v.Vector3 targetPos, double len1, double len2) {
    v.Vector3 direction = targetPos - rootPos;
    double distance = direction.length;
    if (distance > (len1 + len2)) {
      direction.normalize();
      targetPos = rootPos + (direction * (len1 + len2));
      distance = len1 + len2;
    }
    double cosAlpha = (len1 * len1 + distance * distance - len2 * len2) / (2 * len1 * distance);
    double alpha = acos(cosAlpha.clamp(-1.0, 1.0));
    v.Vector3 armAxis = direction.normalized();

    v.Vector3? pole;
    if (jointNode.id.contains('Knee')) pole = v.Vector3(0, 0, -1);
    else if (jointNode.id.contains('Elbow')) pole = v.Vector3(0, 0, 1);

    v.Vector3 bendNormal;
    if (pole != null) {
       bendNormal = armAxis.cross(pole);
       if (bendNormal.length < 0.001) bendNormal = armAxis.cross(v.Vector3(1, 0, 0));
    } else {
       v.Vector3 currentLimb = jointNode.position - rootPos;
       bendNormal = armAxis.cross(currentLimb);
    }

    if (bendNormal.length < 0.001) bendNormal = v.Vector3(1, 0, 0);
    bendNormal.normalize();

    v.Quaternion q = v.Quaternion.axisAngle(bendNormal, alpha);
    jointNode.position.setFrom(rootPos + (q.rotate(armAxis) * len1));
    effectorNode.position.setFrom(targetPos);
  }

  @override
  Widget build(BuildContext context) {
    _refreshNodeCache();
    final styleLabel = TextStyle(color: Colors.white70, fontSize: 10);
    final double panelWidth = 50.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        bool showRotate = _selectedNodeId != null && ['head', 'lHand', 'rHand', 'lFoot', 'rFoot'].contains(_selectedNodeId);

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
                    onPanStart: (_) => _onNodeSelected(node.id),
                    onPanUpdate: (details) => setState(() => _updateBonePosition(node.id, details.delta)),
                    onTap: () => _onNodeSelected(node.id),
                    child: Container(
                      width: 20, height: 20,
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
                    // Top Mode Switcher
                    Positioned(
                      top: 10, left: 0, right: 0,
                      child: Center(
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _modeBtn("Pose", EditorMode.pose),
                              Container(margin: EdgeInsets.symmetric(horizontal: 8), width: 1, height: 16, color: Colors.white30),
                              _modeBtn("Animate", EditorMode.animate),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Left Panel (Views, Height, Zoom) - Moved Up
                    Positioned(
                      top: 50, left: 5, width: panelWidth,
                      child: Column(
                         crossAxisAlignment: CrossAxisAlignment.start,
                         children: [
                           Container(
                             decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                             child: Column(
                               children: [
                                 _viewTextBtn("F", CameraView.free),
                                 _viewTextBtn("X", CameraView.side, Colors.red),
                                 _viewTextBtn("Y", CameraView.top, Colors.green),
                                 _viewTextBtn("Z", CameraView.front, Colors.blue),
                               ],
                             ),
                           ),
                           const SizedBox(height: 15),
                           _verticalSlider(_cameraHeight, -200, 200, (v) => setState(() => _cameraHeight = v), "Hgt"),
                           const SizedBox(height: 10),
                           _verticalSlider(_zoom, 0.5, 10.0, (v) => setState(() => _zoom = v), "Zm"),
                         ],
                      ),
                    ),

                    // Right Panel (Axis, Head, Line, Rotate) - Moved Up
                    Positioned(
                      top: 50, right: 5, width: panelWidth,
                      child: Column(
                         crossAxisAlignment: CrossAxisAlignment.end,
                         children: [
                           Container(
                             decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                             child: Column(
                               children: [
                                 _axisBtn("F", AxisMode.none),
                                 _axisBtn("X", AxisMode.x, Colors.red),
                                 _axisBtn("Y", AxisMode.y, Colors.green),
                                 _axisBtn("Z", AxisMode.z, Colors.blue),
                               ],
                             ),
                           ),
                           const SizedBox(height: 15),
                           _verticalSlider(widget.controller.skeleton.headRadius, 2.0, 15.0,
                             (v) => setState(() => widget.controller.skeleton.headRadius = v), "Head"),
                           const SizedBox(height: 10),
                           _verticalSlider(widget.controller.skeleton.strokeWidth, 1.0, 10.0,
                             (v) => setState(() => widget.controller.skeleton.strokeWidth = v), "Line"),
                           if (showRotate) ...[
                             const SizedBox(height: 10),
                             _verticalSlider(_currentRotationValue, -pi, pi, (v) {
                                setState(() {
                                  _currentRotationValue = v;
                                  _applyRotation(_selectedNodeId!, v);
                                });
                             }, "Rot", Colors.orangeAccent),
                           ],
                         ],
                      ),
                    ),

                    // Bottom Control Bar
                    Positioned(
                      bottom: 5, left: 5, right: 5,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.controller.mode == EditorMode.animate)
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              margin: EdgeInsets.only(bottom: 6),
                              decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
                              child: Column(
                                children: [
                                  // Animation Clip Selector
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        ..._projectClips.map((clip) => _clipChip(clip.name, () => _activateClip(clip))),
                                        IconButton(
                                          icon: Icon(Icons.add_circle, color: Colors.greenAccent, size: 20),
                                          onPressed: _promptAddAnimation,
                                          padding: EdgeInsets.zero,
                                          constraints: BoxConstraints(),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Playback Controls
                                  Row(
                                    children: [
                                      GestureDetector(
                                        onTap: _togglePlayback,
                                        child: Icon(
                                          widget.controller.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                                          color: Colors.white, size: 32
                                        ),
                                      ),
                                      if (widget.controller.lastModifiedBone != null)
                                        TextButton(
                                          onPressed: _applyBoneToAll,
                                          child: Text("All", style: TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold)),
                                          style: TextButton.styleFrom(padding: EdgeInsets.symmetric(horizontal: 4), minimumSize: Size(30, 30)),
                                        ),
                                      Expanded(
                                        child: SliderTheme(
                                          data: SliderThemeData(trackHeight: 2, thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6)),
                                          child: Slider(
                                            value: widget.controller.currentFrameIndex.clamp(0.0, (widget.controller.activeClip?.frameCount.toDouble() ?? 1) - 0.01),
                                            min: 0,
                                            max: (widget.controller.activeClip?.frameCount.toDouble() ?? 1) - 0.01,
                                            activeColor: Colors.purpleAccent,
                                            onChanged: (v) => setState(() { widget.controller.isPlaying = false; widget.controller.currentFrameIndex = v; }),
                                          ),
                                        ),
                                      ),
                                      Text("${widget.controller.currentFrameIndex.floor()}", style: TextStyle(color: Colors.white, fontSize: 12)),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                          // General Toolbar (Scrollable)
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _textBtn("OBJ", _saveObjToFile, Colors.white24),
                                SizedBox(width: 8),
                                _textBtn("Reset", _resetPoseAndDefaults, Colors.redAccent),
                                SizedBox(width: 8),
                                if (widget.controller.mode == EditorMode.animate && widget.controller.activeClip != null) ...[
                                  _textBtn("ZIP", _exportZip, Colors.purple),
                                  SizedBox(width: 8),
                                ],
                                _textBtn("Save", () async {
                                  await StickmanPersistence.saveProject(
                                    _projectClips,
                                    widget.controller.skeleton.headRadius,
                                    widget.controller.skeleton.strokeWidth
                                  );
                                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Saved")));
                                }, Colors.teal),
                                SizedBox(width: 8),
                                _textBtn("Load", () async {
                                  final p = await StickmanPersistence.loadProject();
                                  if (p != null) {
                                    setState(() {
                                      _projectClips = p.clips;
                                      widget.controller.skeleton.headRadius = p.headRadius;
                                      widget.controller.skeleton.strokeWidth = p.strokeWidth;
                                    });
                                    if(_projectClips.isNotEmpty) _activateClip(_projectClips.first);
                                  }
                                }, Colors.orange),
                              ],
                            ),
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

  // --- COMPACT WIDGETS ---

  Widget _modeBtn(String txt, EditorMode m) {
    bool active = widget.controller.mode == m;
    return InkWell(
      onTap: () => _switchMode(m),
      child: Text(txt, style: TextStyle(
        color: active ? Colors.cyanAccent : Colors.white70,
        fontWeight: active ? FontWeight.bold : FontWeight.normal,
        fontSize: 13
      )),
    );
  }

  // New text-based button for Camera Views to match Axis buttons
  Widget _viewTextBtn(String txt, CameraView v, [Color c = Colors.white]) {
    bool active = _cameraView == v;
    return InkWell(
      onTap: () => setState(() => _cameraView = v),
      child: Container(
        width: 30, height: 30,
        alignment: Alignment.center,
        margin: EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(color: active ? Colors.blueAccent : Colors.transparent, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.white24)),
        child: Text(txt, style: TextStyle(color: active ? Colors.white : c, fontWeight: FontWeight.bold, fontSize: 12)),
      ),
    );
  }

  // Legacy icon button - kept just in case, but replaced in UI
  Widget _iconBtn(IconData icon, CameraView v) {
    bool active = _cameraView == v;
    return InkWell(
      onTap: () => setState(() => _cameraView = v),
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(color: active ? Colors.blueAccent : Colors.transparent, borderRadius: BorderRadius.circular(4)),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }

  Widget _axisBtn(String txt, AxisMode m, [Color c = Colors.white]) {
    bool active = _axisMode == m;
    return InkWell(
      onTap: () => setState(() => _axisMode = m),
      child: Container(
        width: 30, height: 30,
        alignment: Alignment.center,
        margin: EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(color: active ? Colors.amber : Colors.transparent, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.white24)),
        child: Text(txt, style: TextStyle(color: active ? Colors.black : c, fontWeight: FontWeight.bold, fontSize: 12)),
      ),
    );
  }

  Widget _verticalSlider(double val, double min, double max, Function(double) chg, String label, [Color activeColor = Colors.deepPurpleAccent]) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: Colors.white70, fontSize: 9)),
        SizedBox(
          height: 100,
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderThemeData(trackHeight: 3, thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6)),
              child: Slider(
                value: val.clamp(min, max),
                min: min, max: max,
                activeColor: activeColor,
                onChanged: chg,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _smallBtn(IconData icon, String lbl, VoidCallback tap, Color bg) {
    return ElevatedButton.icon(
      icon: Icon(icon, size: 14),
      label: Text(lbl, style: TextStyle(fontSize: 11)),
      style: ElevatedButton.styleFrom(
        backgroundColor: bg, foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        minimumSize: Size(0, 26),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: tap,
    );
  }

  Widget _textBtn(String txt, VoidCallback tap, Color bg) {
    return ElevatedButton(
      child: Text(txt, style: TextStyle(fontSize: 11)),
      style: ElevatedButton.styleFrom(
        backgroundColor: bg, foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        minimumSize: Size(0, 30),
      ),
      onPressed: tap,
    );
  }

  Widget _clipChip(String label, VoidCallback tap) {
    bool active = widget.controller.activeClip?.name == label;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: tap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: active ? Colors.blue : Colors.grey[800],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: active ? Colors.blueAccent : Colors.transparent)
          ),
          child: Text(label, style: TextStyle(color: Colors.white, fontSize: 10)),
        ),
      ),
    );
  }

  // --- HELPERS ---
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
