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

class StickmanPoseEditor extends StatefulWidget {
  final StickmanController controller;

  const StickmanPoseEditor({Key? key, required this.controller}) : super(key: key);

  @override
  State<StickmanPoseEditor> createState() => _StickmanPoseEditorState();
}

class _StickmanPoseEditorState extends State<StickmanPoseEditor> {
  late Map<String, StickmanNode> _nodes;

  // --- NEW: Animation Cache (Preserves edits) ---
  final Map<String, StickmanClip> _clipCache = {};

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

  // --- NEW: Load or Generate Logic ---
  /// Checks if the clip exists in cache. If so, loads it (with edits).
  /// If not, generates it, saves to cache, then loads it.
  void _loadOrGenerateClip(String key, StickmanClip Function() generator) {
    if (!_clipCache.containsKey(key)) {
      _clipCache[key] = generator();
    }
    _loadClip(_clipCache[key]!);
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

      // CRITICAL: Automatically save the change to the active clip
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

              // Handles
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
                    // Top Bar
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

                    // Left Column (Scrollable to prevent overflow)
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

                    // Right Column (Scrollable)
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

                    // Bottom: Animation/Export
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
                                          if (widget.controller.activeClip != null) {
                                            await StickmanPersistence.saveClip(widget.controller.activeClip!);
                                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Project saved!")));
                                          }
                                        },
                                      ),
                                      const SizedBox(width: 10),
                                      ElevatedButton.icon(
                                        icon: Icon(Icons.folder_open, size: 16),
                                        label: Text("Load Project"),
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                                        onPressed: () async {
                                          final clip = await StickmanPersistence.loadClip();
                                          if (clip != null) _loadClip(clip);
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
                                        // UPDATED: Use _loadOrGenerateClip to check cache first!
                                        _clipButton("Run", () => _loadOrGenerateClip("Run", () => StickmanGenerator.generateRun(widget.controller.skeleton))),
                                        _clipButton("Jump", () => _loadOrGenerateClip("Jump", () => StickmanGenerator.generateJump(widget.controller.skeleton))),
                                        _clipButton("Kick", () => _loadOrGenerateClip("Kick", () => StickmanGenerator.generateKick(widget.controller.skeleton))),
                                        _clipButton("+", () {
                                          _loadClip(StickmanGenerator.generateEmpty(widget.controller.skeleton));
                                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("New Animation Created")));
                                        }),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: Icon(widget.controller.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                                        onPressed: _togglePlayback,
                                      ),
                                      if (widget.controller.lastModifiedBone != null)
                                        IconButton(
                                          icon: Icon(Icons.copy_all, color: Colors.amber),
                                          onPressed: _applyBoneToAll,
                                          tooltip: "Apply Pose",
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

  void _copyPoseToClipboard() {
    final skel = widget.controller.skeleton;
    final buffer = StringBuffer();
    String format(v.Vector3 v) => "${v.x.toStringAsFixed(1)}, ${v.y.toStringAsFixed(1)}, ${v.z.toStringAsFixed(1)}";
    buffer.writeln("// Pose Data...");
    buffer.writeln(skel.toJson().toString());
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Dart Code copied!")));
  }

  Future<void> _saveObjToFile() async {
    final obj = StickmanExporter.generateObjString(widget.controller.skeleton);
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/stickman.obj');
    await file.writeAsString(obj);
    await Share.shareXFiles([XFile(file.path)], text: 'Stickman 3D Model');
  }

  void _applyBoneToAll() {
    widget.controller.propagatePoseToAllFrames();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Applied ${widget.controller.lastModifiedBone} to all frames")));
  }

  Future<void> _exportZip() async {
    if (widget.controller.activeClip == null) return;
    final bytes = await StickmanExporter.exportClipToZip(widget.controller.activeClip!);
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/animation.zip');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles([XFile(file.path)], text: 'Stickman Animation ZIP');
  }
}
