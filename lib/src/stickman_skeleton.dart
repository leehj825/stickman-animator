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
}
