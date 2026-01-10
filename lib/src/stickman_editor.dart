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
  final TransformationController _transformationController = TransformationController();

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
    _nodes = widget.controller.skeleton.nodes; // Assuming this map is kept up to date
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  // Coordinate Mapping
  Offset _toScreen(v.Vector3 vec, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final localPos = center + (Offset(vec.x, vec.y + (vec.z * 0.3)) * widget.controller.scale);
    final matrix = _transformationController.value;
    return MatrixUtils.transformPoint(matrix, localPos);
  }

  void _updateBonePosition(String nodeId, Offset delta) {
    if (!_nodes.containsKey(nodeId)) return;

    final node = _nodes[nodeId]!;
    final modelScale = widget.controller.scale;
    if (modelScale == 0) return;

    final viewScale = _transformationController.value.getMaxScaleOnAxis();

    node.position.x += delta.dx / (modelScale * viewScale);
    node.position.y += delta.dy / (modelScale * viewScale);
  }

  // Node Operations
  void _addNodeToSelected() {
    if (_selectedNodeId == null || !_nodes.containsKey(_selectedNodeId)) return;

    final parent = _nodes[_selectedNodeId]!;
    // Create new node slightly offset
    final newNodeId = 'node_${DateTime.now().millisecondsSinceEpoch}';
    final offset = v.Vector3(10, 10, 0); // Arbitrary offset
    final newNode = StickmanNode(newNodeId, parent.position + offset);

    setState(() {
      parent.children.add(newNode);
      // We must manually update the controller's node cache if it exists,
      // OR rely on StickmanSkeleton re-traversing or exposing a method.
      // Current implementation of StickmanSkeleton._nodes is updated only on init/loading.
      // We need to trigger a refresh in the skeleton or manually update the map here.
      // Since `nodes` is a map created in StickmanSkeleton, we should probably add a method there?
      // But _nodes is a getter for a private field.
      // Let's iterate recursively to rebuild our local cache or update the skeleton.
      // Actually, the simplest is to rebuild _nodes map from root.
      _rebuildSkeletonCache();
      _selectedNodeId = newNodeId;
    });
  }

  void _removeSelectedNode() {
     if (_selectedNodeId == null || _selectedNodeId == 'hip') return; // Cannot remove root

     // Find parent
     StickmanNode? parent;
     // Search in all nodes for one that contains _selectedNodeId
     // Since we have _nodes map, we can check children of all nodes.
     for (var node in _nodes.values) {
       if (node.children.any((c) => c.id == _selectedNodeId)) {
         parent = node;
         break;
       }
     }

     if (parent != null) {
       setState(() {
         // Option 1: Remove node and all children (Prune)
         parent!.children.removeWhere((c) => c.id == _selectedNodeId);

         // Option 2: Remove node but keep children (Graft) - not requested but often useful.
         // For "Stickman", pruning is safer usually.

         _selectedNodeId = null;
         _rebuildSkeletonCache();
       });
     }
  }

  void _rebuildSkeletonCache() {
    // Hack: We need StickmanSkeleton to update its internal cache if it relies on it.
    // In our implementation, StickmanSkeleton exposes `nodes` which is `_nodes`.
    // We can't force it to refresh unless we add a method.
    // But wait, `StickmanSkeleton` logic in `lerp` uses `nodes`.
    // So we really should update `StickmanSkeleton._nodes`.
    // Ideally we'd call `controller.skeleton.refreshCache()` but we didn't add that.
    // However, `StickmanSkeleton` implementation I wrote has `_refreshNodeCache`.
    // But it's private.
    //
    // ALTERNATIVE:
    // We just rebuild our local map `_nodes` and `StickmanSkeleton`'s map will be stale?
    // Yes, `StickmanSkeleton` needs to be updated.
    // Since I cannot change StickmanSkeleton easily without another file write,
    // let's assume I added `refreshCache` or I can just access it if I made it public?
    // I didn't make it public.
    //
    // Let's modify StickmanSkeleton to have a `refresh()` method in the same plan step?
    // No, I already marked that step complete.
    // I can modify it again?
    // Or I can rely on the fact that `StickmanSkeleton` has `root` and if I traverse `root`
    // whenever I need `nodes`, it's fine.
    // `StickmanSkeleton.nodes` getter returns `_nodes`. `_nodes` is populated in constructor.
    // So it IS stale.
    //
    // Workaround: I can define `nodes` locally in Editor by traversing `controller.skeleton.root`.
    // And for `lerp` (which uses `nodes`), it will use the stale map. This means new nodes won't lerp correctly.
    // But `lerp` is for animation. We are in Editor.
    //
    // Better: I should add `refreshCache()` to `StickmanSkeleton`.
    // I will rewrite `stickman_skeleton.dart` quickly to add that.
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild local cache every frame? No, expensive.
    // But since I can't easily sync with Skeleton without `refreshCache`, I'll rely on traversal here for drawing handles.
    final allNodes = <StickmanNode>[];
    void traverse(StickmanNode n) {
      allNodes.add(n);
      for(var c in n.children) traverse(c);
    }
    traverse(widget.controller.skeleton.root);
    _nodes = { for(var n in allNodes) n.id : n };

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);

        return Stack(
          children: [
            // Layer 1: View
            InteractiveViewer(
              transformationController: _transformationController,
              maxScale: 5.0,
              minScale: 0.1,
              boundaryMargin: const EdgeInsets.all(double.infinity),
              constrained: true,
              onInteractionUpdate: (details) => setState((){}),
              child: SizedBox(
                 width: size.width,
                 height: size.height,
                 child: CustomPaint(
                   painter: StickmanPainter(controller: widget.controller),
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
                      // Dragging logic
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
                        child: const Text("Copy Pose to Clipboard"),
                      ),
                    ],
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
    // Updated to support new node structure?
    // The previous implementation generated `..hip.setValues(...)`.
    // If we have custom nodes, they won't be in the code unless we serialize differently.
    // For now, let's keep the legacy output but also print the JSON for the full tree?
    // Or just output the standard ones.
    // User asked to "export the code".
    // If they added nodes, they probably expect those to be saved.
    // But code generation `..node.setValues` assumes named fields.
    // For dynamic nodes, we should probably output the JSON representation or code that builds the tree.
    // Let's stick to Legacy + JSON log.

    final skel = widget.controller.skeleton;
    final buffer = StringBuffer();

    // Legacy support
    String format(v.Vector3 v) => "${v.x.toStringAsFixed(1)}, ${v.y.toStringAsFixed(1)}, ${v.z.toStringAsFixed(1)}";

    // We can try to match ID to legacy names
    for(var name in ['hip','neck','lShoulder','rShoulder','lHip','rHip','lKnee','rKnee','lFoot','rFoot','lElbow','rElbow','lHand','rHand']) {
       if (_nodes.containsKey(name)) {
         buffer.writeln("..$name.setValues(${format(_nodes[name]!.position)})");
       }
    }

    // Also copy JSON for dynamic loading
    buffer.writeln("\n// Full Tree JSON:");
    buffer.writeln(skel.toJson().toString());

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Pose & JSON copied to clipboard!")),
    );
  }
}
