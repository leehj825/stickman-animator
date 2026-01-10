import 'package:vector_math/vector_math_64.dart' as v;

/// 1. THE SKELETON: Holds the raw 3D data of the stickman
class StickmanSkeleton {
  v.Vector3 hip = v.Vector3.zero();
  v.Vector3 neck = v.Vector3.zero();
  v.Vector3 lShoulder = v.Vector3.zero();
  v.Vector3 rShoulder = v.Vector3.zero();
  v.Vector3 lHip = v.Vector3.zero();
  v.Vector3 rHip = v.Vector3.zero();
  v.Vector3 lKnee = v.Vector3.zero();
  v.Vector3 rKnee = v.Vector3.zero();
  v.Vector3 lFoot = v.Vector3.zero();
  v.Vector3 rFoot = v.Vector3.zero();
  v.Vector3 lElbow = v.Vector3.zero();
  v.Vector3 rElbow = v.Vector3.zero();
  v.Vector3 lHand = v.Vector3.zero();
  v.Vector3 rHand = v.Vector3.zero();

  // Helper to get all points as a list for bulk operations
  List<v.Vector3> get allPoints => [
    hip, neck, lShoulder, rShoulder, lHip, rHip,
    lKnee, rKnee, lFoot, rFoot, lElbow, rElbow, lHand, rHand
  ];

  StickmanSkeleton();

  /// Returns a deep copy of the skeleton
  StickmanSkeleton clone() {
    final copy = StickmanSkeleton();
    copy.hip.setFrom(hip);
    copy.neck.setFrom(neck);
    copy.lShoulder.setFrom(lShoulder);
    copy.rShoulder.setFrom(rShoulder);
    copy.lHip.setFrom(lHip);
    copy.rHip.setFrom(rHip);
    copy.lKnee.setFrom(lKnee);
    copy.rKnee.setFrom(rKnee);
    copy.lFoot.setFrom(lFoot);
    copy.rFoot.setFrom(rFoot);
    copy.lElbow.setFrom(lElbow);
    copy.rElbow.setFrom(rElbow);
    copy.lHand.setFrom(lHand);
    copy.rHand.setFrom(rHand);
    return copy;
  }

  /// Linearly interpolates all bone vectors between this and other based on t (0.0 to 1.0).
  /// Modifies this skeleton.
  void lerp(StickmanSkeleton other, double t) {
    _lerpVec(hip, other.hip, t);
    _lerpVec(neck, other.neck, t);
    _lerpVec(lShoulder, other.lShoulder, t);
    _lerpVec(rShoulder, other.rShoulder, t);
    _lerpVec(lHip, other.lHip, t);
    _lerpVec(rHip, other.rHip, t);
    _lerpVec(lKnee, other.lKnee, t);
    _lerpVec(rKnee, other.rKnee, t);
    _lerpVec(lFoot, other.lFoot, t);
    _lerpVec(rFoot, other.rFoot, t);
    _lerpVec(lElbow, other.lElbow, t);
    _lerpVec(rElbow, other.rElbow, t);
    _lerpVec(lHand, other.lHand, t);
    _lerpVec(rHand, other.rHand, t);
  }

  void _lerpVec(v.Vector3 current, v.Vector3 target, double t) {
    current.x = current.x + (target.x - current.x) * t;
    current.y = current.y + (target.y - current.y) * t;
    current.z = current.z + (target.z - current.z) * t;
  }

  Map<String, dynamic> toJson() {
    return {
      'hip': _vecToList(hip),
      'neck': _vecToList(neck),
      'lShoulder': _vecToList(lShoulder),
      'rShoulder': _vecToList(rShoulder),
      'lHip': _vecToList(lHip),
      'rHip': _vecToList(rHip),
      'lKnee': _vecToList(lKnee),
      'rKnee': _vecToList(rKnee),
      'lFoot': _vecToList(lFoot),
      'rFoot': _vecToList(rFoot),
      'lElbow': _vecToList(lElbow),
      'rElbow': _vecToList(rElbow),
      'lHand': _vecToList(lHand),
      'rHand': _vecToList(rHand),
    };
  }

  factory StickmanSkeleton.fromJson(Map<String, dynamic> json) {
    final skel = StickmanSkeleton();
    void set(v.Vector3 vec, String key) {
      if (json.containsKey(key)) {
        final list = json[key] as List;
        vec.setValues(list[0].toDouble(), list[1].toDouble(), list[2].toDouble());
      }
    }
    set(skel.hip, 'hip');
    set(skel.neck, 'neck');
    set(skel.lShoulder, 'lShoulder');
    set(skel.rShoulder, 'rShoulder');
    set(skel.lHip, 'lHip');
    set(skel.rHip, 'rHip');
    set(skel.lKnee, 'lKnee');
    set(skel.rKnee, 'rKnee');
    set(skel.lFoot, 'lFoot');
    set(skel.rFoot, 'rFoot');
    set(skel.lElbow, 'lElbow');
    set(skel.rElbow, 'rElbow');
    set(skel.lHand, 'lHand');
    set(skel.rHand, 'rHand');
    return skel;
  }

  List<double> _vecToList(v.Vector3 vec) => [vec.x, vec.y, vec.z];
}
