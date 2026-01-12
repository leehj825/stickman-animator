import 'dart:math';
import 'package:vector_math/vector_math_64.dart' as v;
import 'stickman_skeleton.dart';
import 'stickman_animation.dart';

class StickmanGenerator {

  // --- HELPER: Measure existing bone lengths ---
  static double _getDist(StickmanSkeleton skel, String id1, String id2) {
    final n1 = skel.getBone(id1);
    final n2 = skel.getBone(id2);
    // Fallback defaults only if nodes are completely missing
    if (n1 == null || n2 == null) {
      if (id1.contains('Leg') || id2.contains('Leg') || id1.contains('Knee') || id1.contains('Foot')) return 13.0;
      return 10.0;
    }
    return n1.distanceTo(n2);
  }

  // --- HELPER: Solve Joint Position (IK with Dynamic Lengths) ---
  static void _setLimbIK(
      StickmanSkeleton pose,
      String side, // 'l' or 'r'
      String limb, // 'Arm' or 'Leg'
      v.Vector3 targetPos,
      v.Vector3 bendHint,
      double len1, // Upper Limb Length
      double len2  // Lower Limb Length
  ) {
    // 1. Identify Nodes
    String rootId = (limb == 'Leg') ? 'hip' : 'neck';
    String jointId = '$side${limb == 'Leg' ? 'Knee' : 'Elbow'}';
    String effectorId = '$side${limb == 'Leg' ? 'Foot' : 'Hand'}';

    v.Vector3 rootPos = (limb == 'Leg') ? pose.hip : pose.neck;

    // 2. IK Math (Circle Intersection / Law of Cosines)
    v.Vector3 dir = targetPos - rootPos;
    double dist = dir.length;

    // Clamp reach to avoid popping/stretching
    double totalLen = len1 + len2;
    if (dist >= totalLen - 0.001) {
      dir.normalize();
      targetPos = rootPos + dir * (totalLen - 0.001);
      dist = totalLen - 0.001;
    }

    // Law of Cosines for angle at Root
    // c^2 = a^2 + b^2 - 2ab cos(C)
    double cosAlpha = (len1*len1 + dist*dist - len2*len2) / (2 * len1 * dist);
    double alpha = acos(cosAlpha.clamp(-1.0, 1.0));

    // Rotation Axis
    // We need a normal vector perpendicular to the limb plane.
    v.Vector3 armAxis = dir.normalized();
    v.Vector3 bendNormal = armAxis.cross(bendHint).normalized();

    // If aligned (straight), fallback to X axis
    if (bendNormal.length < 0.001) bendNormal = v.Vector3(1, 0, 0);

    // Rotate root->target vector by alpha around bendNormal
    v.Quaternion q = v.Quaternion.axisAngle(bendNormal, alpha);
    v.Vector3 jointPos = rootPos + (q.rotate(armAxis) * len1);

    // 3. Set Positions
    if (jointId == 'lKnee') pose.lKnee = jointPos;
    if (jointId == 'rKnee') pose.rKnee = jointPos;
    if (jointId == 'lElbow') pose.lElbow = jointPos;
    if (jointId == 'rElbow') pose.rElbow = jointPos;

    if (effectorId == 'lFoot') pose.lFoot = targetPos;
    if (effectorId == 'rFoot') pose.rFoot = targetPos;
    if (effectorId == 'lHand') pose.lHand = targetPos;
    if (effectorId == 'rHand') pose.rHand = targetPos;
  }

  static void _applyStyle(StickmanSkeleton pose, StickmanSkeleton? style) {
    if (style != null) {
      pose.headRadius = style.headRadius;
      pose.strokeWidth = style.strokeWidth;
    }
  }

  // --- 1. RUN ANIMATION (Corrected: Front is Right / +Z) ---
  static StickmanClip generateRun(StickmanSkeleton? style) {
    // Measure the user's current skeleton
    final measureSkel = style ?? StickmanSkeleton();

    double spineLen = _getDist(measureSkel, 'hip', 'neck');

    double lThigh = _getDist(measureSkel, 'hip', 'lKnee');
    double lShin = _getDist(measureSkel, 'lKnee', 'lFoot');
    double rThigh = _getDist(measureSkel, 'hip', 'rKnee');
    double rShin = _getDist(measureSkel, 'rKnee', 'rFoot');

    double lUpperArm = _getDist(measureSkel, 'neck', 'lElbow');
    double lForeArm = _getDist(measureSkel, 'lElbow', 'lHand');
    double rUpperArm = _getDist(measureSkel, 'neck', 'rElbow');
    double rForeArm = _getDist(measureSkel, 'rElbow', 'rHand');

    List<StickmanKeyframe> frames = [];
    int totalFrames = 24;

    for (int i = 0; i < totalFrames; i++) {
      double t = i / totalFrames;
      double angle = t * 2 * pi;

      StickmanSkeleton pose = StickmanSkeleton();
      _applyStyle(pose, style);

      // Body Bobbing
      pose.hip.y = cos(angle * 2) * 1.5;

      // Lean Forward (Toward Right / Positive Z)
      double leanAmount = 5.0;
      // Calculate Y offset to maintain exact spine length (Pythagoras)
      double neckY = -sqrt(max(0, spineLen * spineLen - leanAmount * leanAmount));
      pose.neck.setValues(0, pose.hip.y + neckY, leanAmount);

      // --- Leg Cycle ---
      // Left Leg
      double lPhase = angle;
      v.Vector3 lTarget = _calculateRunFootPos(lPhase, isLeft: true, baseHeight: 25.0);
      // Knee Bend: Forward (+Z)
      _setLimbIK(pose, 'l', 'Leg', lTarget, v.Vector3(0, 0, 1), lThigh, lShin);

      // Right Leg
      double rPhase = angle + pi;
      v.Vector3 rTarget = _calculateRunFootPos(rPhase, isLeft: false, baseHeight: 25.0);
      _setLimbIK(pose, 'r', 'Leg', rTarget, v.Vector3(0, 0, 1), rThigh, rShin);

      // --- Arm Cycle (Opposite to legs) ---
      // Left Arm swings with Right Leg
      v.Vector3 lArmT = _calculateRunHandPos(rPhase, isLeft: true, spineTop: pose.neck);
      // Elbow Bend: Backward (-Z)
      _setLimbIK(pose, 'l', 'Arm', lArmT, v.Vector3(0, 0, -1), lUpperArm, lForeArm);

      // Right Arm swings with Left Leg
      v.Vector3 rArmT = _calculateRunHandPos(lPhase, isLeft: false, spineTop: pose.neck);
      _setLimbIK(pose, 'r', 'Arm', rArmT, v.Vector3(0, 0, -1), rUpperArm, rForeArm);

      // Update Head
      pose.setHead(pose.neck + v.Vector3(0, -8, 0));

      frames.add(StickmanKeyframe(pose: pose, frameIndex: i));
    }
    return StickmanClip(name: "Run", keyframes: frames, fps: 30, isLooping: true);
  }

  static v.Vector3 _calculateRunFootPos(double angle, {required bool isLeft, required double baseHeight}) {
    double x = isLeft ? -4 : 4;
    double strideLen = 15.0;
    double liftHeight = 8.0;

    double sinA = sin(angle);

    // Z: Forward/Back motion
    // Running Right (+Z):
    // Stance (Foot on ground, moving back relative to hips): Z decreases.
    // Swing (Foot in air, moving forward): Z increases.
    // sin(angle): 0 -> 1 -> 0 -> -1
    // z = -sinA * stride;
    // 0 to pi (sin > 0) -> z is negative (Moving Left/Back). Correct for Stance.
    // pi to 2pi (sin < 0) -> z is positive (Moving Right/Forward). Correct for Swing.
    double z = -sinA * strideLen;

    // Y: Up/Down.
    // Lift during Swing phase (pi to 2pi, where sinA < 0)
    double y = baseHeight;
    if (sinA < 0) {
       y -= sin(angle * 1) * liftHeight * -1.0; // Arch up
       y = min(baseHeight, y);
    }

    return v.Vector3(x, y, z);
  }

  static v.Vector3 _calculateRunHandPos(double angle, {required bool isLeft, required v.Vector3 spineTop}) {
    double x = isLeft ? -8 : 8;
    double swing = sin(angle) * 12.0;

    // Arm swings opposite to leg.
    // For +Z movement, arms swing similarly along Z.
    double z = swing;
    double y = -5.0 + abs(cos(angle)) * 2; // Slight bob

    // Relative to Spine Top
    return spineTop + v.Vector3(x, 15 + y, z);
  }

  static double abs(double v) => v > 0 ? v : -v;

  // --- 2. JUMP ANIMATION ---
  static StickmanClip generateJump(StickmanSkeleton? style) {
    final measureSkel = style ?? StickmanSkeleton();
    double spineLen = _getDist(measureSkel, 'hip', 'neck');

    double lThigh = _getDist(measureSkel, 'hip', 'lKnee');
    double lShin = _getDist(measureSkel, 'lKnee', 'lFoot');
    double rThigh = _getDist(measureSkel, 'hip', 'rKnee');
    double rShin = _getDist(measureSkel, 'rKnee', 'rFoot');

    double lUpperArm = _getDist(measureSkel, 'neck', 'lElbow');
    double lForeArm = _getDist(measureSkel, 'lElbow', 'lHand');
    double rUpperArm = _getDist(measureSkel, 'neck', 'rElbow');
    double rForeArm = _getDist(measureSkel, 'rElbow', 'rHand');

    List<StickmanKeyframe> frames = [];
    int totalFrames = 30;

    for (int i = 0; i < totalFrames; i++) {
      double t = i / totalFrames;
      StickmanSkeleton pose = StickmanSkeleton();
      _applyStyle(pose, style);

      // Phases: 0.0-0.3 (Squat), 0.3-0.5 (Launch), 0.5-0.8 (Air), 0.8-1.0 (Land)
      double hipY = 0;
      if (t < 0.2) { hipY = _lerp(0, 15, t/0.2); } // Squat
      else if (t < 0.5) { hipY = _lerp(15, -20, (t-0.2)/0.3); } // Up
      else if (t < 0.8) { hipY = _lerp(-20, 0, (t-0.5)/0.3); } // Down
      else { hipY = _lerp(0, 0, (t-0.8)/0.2); } // Recover

      pose.hip.y = hipY;
      pose.neck.setValues(0, hipY - spineLen, 0);

      // Feet planted (until jump)
      double footY = 25;
      if (t > 0.3 && t < 0.8) footY = hipY + 25 - 5; // Lift feet in air

      // Knees bend Forward (+Z)
      _setLimbIK(pose, 'l', 'Leg', v.Vector3(-4, footY, 0), v.Vector3(0,0,1), lThigh, lShin);
      _setLimbIK(pose, 'r', 'Leg', v.Vector3(4, footY, 0), v.Vector3(0,0,1), rThigh, rShin);

      // Arms swing
      double armZ = -5;
      double armY = 0;
      if (t < 0.2) { armZ = -10; armY = 5; } // Back (-Z)
      else if (t < 0.5) { armZ = 15; armY = -15; } // Up/Forward (+Z)
      else { armZ = 0; armY = 0; }

      // Elbows bend Backward (-Z)
      _setLimbIK(pose, 'l', 'Arm', pose.neck + v.Vector3(-8, 10+armY, armZ), v.Vector3(0,0,-1), lUpperArm, lForeArm);
      _setLimbIK(pose, 'r', 'Arm', pose.neck + v.Vector3(8, 10+armY, armZ), v.Vector3(0,0,-1), rUpperArm, rForeArm);

      pose.setHead(pose.neck + v.Vector3(0,-8,0));
      frames.add(StickmanKeyframe(pose: pose, frameIndex: i));
    }
    return StickmanClip(name: "Jump", keyframes: frames, fps: 30, isLooping: false);
  }

  // --- 3. KICK ANIMATION ---
  static StickmanClip generateKick(StickmanSkeleton? style) {
    final measureSkel = style ?? StickmanSkeleton();
    double spineLen = _getDist(measureSkel, 'hip', 'neck');

    double lThigh = _getDist(measureSkel, 'hip', 'lKnee');
    double lShin = _getDist(measureSkel, 'lKnee', 'lFoot');
    double rThigh = _getDist(measureSkel, 'hip', 'rKnee');
    double rShin = _getDist(measureSkel, 'rKnee', 'rFoot');

    double lUpperArm = _getDist(measureSkel, 'neck', 'lElbow');
    double lForeArm = _getDist(measureSkel, 'lElbow', 'lHand');
    double rUpperArm = _getDist(measureSkel, 'neck', 'rElbow');
    double rForeArm = _getDist(measureSkel, 'rElbow', 'rHand');

    List<StickmanKeyframe> frames = [];
    int totalFrames = 30;

    for (int i = 0; i < totalFrames; i++) {
      double t = i / totalFrames;
      StickmanSkeleton pose = StickmanSkeleton();
      _applyStyle(pose, style);

      // Stance
      v.Vector3 hip = v.Vector3(0, 0, 0);
      v.Vector3 lFoot = v.Vector3(-5, 25, 5); // Left foot
      v.Vector3 rFoot = v.Vector3(5, 25, -5); // Right foot

      if (t < 0.3) { // Chamber
         double pt = t/0.3;
         hip.x = _lerp(0, -5, pt);
         rFoot = v.Vector3(5, _lerp(25, 10, pt), _lerp(-5, 5, pt)); // Lift
      } else if (t < 0.6) { // Kick
         double pt = (t-0.3)/0.3;
         hip.x = -5;
         // High kick Forward (+Z)
         rFoot = v.Vector3(5, _lerp(10, -5, pt), _lerp(5, 20, pt));
      } else { // Return
         double pt = (t-0.6)/0.4;
         hip.x = _lerp(-5, 0, pt);
         rFoot = v.Vector3(5, _lerp(-5, 25, pt), _lerp(20, -5, pt));
      }

      pose.hip = hip;
      pose.neck.setValues(0, hip.y - spineLen, 0);

      _setLimbIK(pose, 'l', 'Leg', lFoot, v.Vector3(0,0,1), lThigh, lShin);
      // Right leg kicks forward (+Z)
      _setLimbIK(pose, 'r', 'Leg', rFoot, v.Vector3(0,0,1), rThigh, rShin);

      // Guard Arms
      _setLimbIK(pose, 'l', 'Arm', pose.neck + v.Vector3(-8, 5, 5), v.Vector3(0,0,-1), lUpperArm, lForeArm);
      _setLimbIK(pose, 'r', 'Arm', pose.neck + v.Vector3(8, 5, -5), v.Vector3(0,0,-1), rUpperArm, rForeArm);

      pose.setHead(pose.neck + v.Vector3(0,-8,0));
      frames.add(StickmanKeyframe(pose: pose, frameIndex: i));
    }
    return StickmanClip(name: "Kick", keyframes: frames, fps: 30, isLooping: false);
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  static StickmanClip generateEmpty(StickmanSkeleton? style) {
    List<StickmanKeyframe> frames = [];
    for(int i=0; i<30; i++) {
        StickmanSkeleton p = style != null ? style.clone() : StickmanSkeleton();
        frames.add(StickmanKeyframe(pose: p, frameIndex: i));
    }
    return StickmanClip(name: "Custom", keyframes: frames, fps: 30, isLooping: true);
  }
}
