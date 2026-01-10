import 'package:vector_math/vector_math_64.dart' as v;

/// Represents a single node (joint) in the skeleton hierarchy
class StickmanNode {
  String id;
  v.Vector3 position;
  List<StickmanNode> children = [];

  StickmanNode(this.id, v.Vector3 pos) : position = v.Vector3.copy(pos);

  StickmanNode clone() {
    final copy = StickmanNode(id, position);
    for (final child in children) {
      copy.children.add(child.clone());
    }
    return copy;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'pos': [position.x, position.y, position.z],
      'children': children.map((c) => c.toJson()).toList(),
    };
  }

  factory StickmanNode.fromJson(Map<String, dynamic> json) {
    final posList = json['pos'] as List;
    final node = StickmanNode(
      json['id'] as String,
      v.Vector3(posList[0].toDouble(), posList[1].toDouble(), posList[2].toDouble()),
    );
    if (json.containsKey('children')) {
      for (var childJson in (json['children'] as List)) {
        node.children.add(StickmanNode.fromJson(childJson));
      }
    }
    return node;
  }
}

/// 1. THE SKELETON: Holds the raw 3D data of the stickman
class StickmanSkeleton {
  late StickmanNode root;

  // Cache for fast access to standard bones
  // Map ID -> Node
  final Map<String, StickmanNode> _nodes = {};

  StickmanSkeleton() {
    // Build Default Hierarchy
    // Hip is root
    root = StickmanNode('hip', v.Vector3.zero());

    final neck = StickmanNode('neck', v.Vector3.zero());
    root.children.add(neck);

    // Head as child of Neck
    final head = StickmanNode('head', v.Vector3.zero());
    neck.children.add(head);

    final lShoulder = StickmanNode('lShoulder', v.Vector3.zero());
    final rShoulder = StickmanNode('rShoulder', v.Vector3.zero());
    neck.children.add(lShoulder);
    neck.children.add(rShoulder);

    final lElbow = StickmanNode('lElbow', v.Vector3.zero());
    lShoulder.children.add(lElbow);
    final lHand = StickmanNode('lHand', v.Vector3.zero());
    lElbow.children.add(lHand);

    final rElbow = StickmanNode('rElbow', v.Vector3.zero());
    rShoulder.children.add(rElbow);
    final rHand = StickmanNode('rHand', v.Vector3.zero());
    rElbow.children.add(rHand);

    final lHip = StickmanNode('lHip', v.Vector3.zero());
    final rHip = StickmanNode('rHip', v.Vector3.zero());
    root.children.add(lHip);
    root.children.add(rHip);

    final lKnee = StickmanNode('lKnee', v.Vector3.zero());
    lHip.children.add(lKnee);
    final lFoot = StickmanNode('lFoot', v.Vector3.zero());
    lKnee.children.add(lFoot);

    final rKnee = StickmanNode('rKnee', v.Vector3.zero());
    rHip.children.add(rKnee);
    final rFoot = StickmanNode('rFoot', v.Vector3.zero());
    rKnee.children.add(rFoot);

    _refreshNodeCache();
  }

  // Private constructor for cloning
  StickmanSkeleton._fromRoot(this.root) {
    _refreshNodeCache();
  }

  void _refreshNodeCache() {
    _nodes.clear();
    void traverse(StickmanNode node) {
      _nodes[node.id] = node;
      for (var c in node.children) traverse(c);
    }
    traverse(root);
  }

  // Helper to get all points as a list for bulk operations (Legacy support + Physics)
  List<v.Vector3> get allPoints {
    final points = <v.Vector3>[];
    void traverse(StickmanNode node) {
      points.add(node.position);
      for (var c in node.children) traverse(c);
    }
    traverse(root);
    return points;
  }

  // Public Access to nodes
  Map<String, StickmanNode> get nodes => _nodes;

  // Legacy Getters and Setters
  v.Vector3 get hip => _nodes['hip']!.position;
  set hip(v.Vector3 v) => _nodes['hip']!.position.setFrom(v);

  v.Vector3 get neck => _nodes['neck']!.position;
  set neck(v.Vector3 v) => _nodes['neck']!.position.setFrom(v);

  // New Head getter/setter (safe access)
  v.Vector3? get head => _nodes['head']?.position;
  void setHead(v.Vector3 v) => _nodes['head']?.position.setFrom(v);

  v.Vector3 get lShoulder => _nodes['lShoulder']!.position;
  set lShoulder(v.Vector3 v) => _nodes['lShoulder']!.position.setFrom(v);

  v.Vector3 get rShoulder => _nodes['rShoulder']!.position;
  set rShoulder(v.Vector3 v) => _nodes['rShoulder']!.position.setFrom(v);

  v.Vector3 get lHip => _nodes['lHip']!.position;
  set lHip(v.Vector3 v) => _nodes['lHip']!.position.setFrom(v);

  v.Vector3 get rHip => _nodes['rHip']!.position;
  set rHip(v.Vector3 v) => _nodes['rHip']!.position.setFrom(v);

  v.Vector3 get lKnee => _nodes['lKnee']!.position;
  set lKnee(v.Vector3 v) => _nodes['lKnee']!.position.setFrom(v);

  v.Vector3 get rKnee => _nodes['rKnee']!.position;
  set rKnee(v.Vector3 v) => _nodes['rKnee']!.position.setFrom(v);

  v.Vector3 get lFoot => _nodes['lFoot']!.position;
  set lFoot(v.Vector3 v) => _nodes['lFoot']!.position.setFrom(v);

  v.Vector3 get rFoot => _nodes['rFoot']!.position;
  set rFoot(v.Vector3 v) => _nodes['rFoot']!.position.setFrom(v);

  v.Vector3 get lElbow => _nodes['lElbow']!.position;
  set lElbow(v.Vector3 v) => _nodes['lElbow']!.position.setFrom(v);

  v.Vector3 get rElbow => _nodes['rElbow']!.position;
  set rElbow(v.Vector3 v) => _nodes['rElbow']!.position.setFrom(v);

  v.Vector3 get lHand => _nodes['lHand']!.position;
  set lHand(v.Vector3 v) => _nodes['lHand']!.position.setFrom(v);

  v.Vector3 get rHand => _nodes['rHand']!.position;
  set rHand(v.Vector3 v) => _nodes['rHand']!.position.setFrom(v);


  /// Returns a deep copy of the skeleton
  StickmanSkeleton clone() {
    return StickmanSkeleton._fromRoot(root.clone());
  }

  /// Linearly interpolates all bone vectors between this and other based on t (0.0 to 1.0).
  void lerp(StickmanSkeleton other, double t) {
    // We assume structure is identical for lerp.
    // If not, we only lerp matching IDs.
    void traverse(StickmanNode myNode) {
      if (other.nodes.containsKey(myNode.id)) {
        final target = other.nodes[myNode.id]!.position;
        _lerpVec(myNode.position, target, t);
      }
      for (var c in myNode.children) traverse(c);
    }
    traverse(root);
  }

  void _lerpVec(v.Vector3 current, v.Vector3 target, double t) {
    current.x = current.x + (target.x - current.x) * t;
    current.y = current.y + (target.y - current.y) * t;
    current.z = current.z + (target.z - current.z) * t;
  }

  Map<String, dynamic> toJson() {
    return root.toJson();
  }

  factory StickmanSkeleton.fromJson(Map<String, dynamic> json) {
    return StickmanSkeleton._fromRoot(StickmanNode.fromJson(json));
  }
}
