import 'dart:math';
import 'package:vector_math/vector_math_64.dart' as v;
import 'stickman_skeleton.dart';
import 'stickman_animation.dart';

class StickmanGenerator {

  // --- HELPER: Solve Joint Position (Exact Lengths) ---
  static void _setLimbIK(
      StickmanSkeleton pose,
      String side, // 'l' or 'r'
      String limb, // 'Arm' or 'Leg'
      v.Vector3 targetPos,
      v.Vector3 bendHint
  ) {
    // 1. Identify Nodes
    String rootId = (limb == 'Leg') ? 'hip' : 'neck';
    String jointId = '$side${limb == 'Leg' ? 'Knee' : 'Elbow'}';
    String effectorId = '$side${limb == 'Leg' ? 'Foot' : 'Hand'}';

    v.Vector3 rootPos = (limb == 'Leg') ? pose.hip : pose.neck;

    // 2. Get Lengths from current pose (assuming style is applied)
    // We assume standard lengths if not set, but we should use the pose's current distance
    // However, since we are generating from scratch, we define standard lengths
    // or assume the pose passed in has the correct lengths.
    // For a generator, we usually want fixed standard lengths or proportional to height.
    double len1 = (limb == 'Leg') ? 13.0 : 10.0;
    double len2 = (limb == 'Leg') ? 13.0 : 10.0;

    // 3. IK Math (Circle Intersection / Law of Cosines)
    v.Vector3 dir = targetPos - rootPos;
    double dist = dir.length;

    // Clamp reach
    if (dist > len1 + len2 - 0.01) {
      dir.normalize();
      targetPos = rootPos + dir * (len1 + len2 - 0.01);
      dist = len1 + len2 - 0.01;
    }

    // Law of Cosines for angle at Root
    // c^2 = a^2 + b^2 - 2ab cos(C) -> len2^2 = len1^2 + dist^2 - 2*len1*dist*cos(alpha)
    double cosAlpha = (len1*len1 + dist*dist - len2*len2) / (2 * len1 * dist);
    double alpha = acos(cosAlpha.clamp(-1.0, 1.0));

    // Rotation Axis
    // We need a normal vector perpendicular to the limb plane.
    // We use the 'bendHint' to define this plane.
    v.Vector3 armAxis = dir.normalized();
    v.Vector3 bendNormal = armAxis.cross(bendHint).normalized();

    // If aligned (straight), fallback to X axis
    if (bendNormal.length == 0) bendNormal = v.Vector3(1, 0, 0);

    // Rotate root->target vector by alpha around bendNormal
    v.Quaternion q = v.Quaternion.axisAngle(bendNormal, alpha);
    v.Vector3 jointPos = rootPos + (q.rotate(armAxis) * len1);

    // 4. Set Positions
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

  // --- 1. RUN ANIMATION (Corrected Direction & Lengths) ---
  static StickmanClip generateRun(StickmanSkeleton? style) {
    List<StickmanKeyframe> frames = [];
    int totalFrames = 24;

    for (int i = 0; i < totalFrames; i++) {
      double t = i / totalFrames;
      double angle = t * 2 * pi;

      StickmanSkeleton pose = StickmanSkeleton();
      _applyStyle(pose, style);

      // Body Bobbing
      pose.hip.y = cos(angle * 2) * 1.5;
      pose.neck.setValues(0, -25 + pose.hip.y + 2, 5); // Lean forward (+Z is forward)

      // --- Leg Cycle ---
      // 0.0 = Left Contact, Right Back
      // 0.5 = Right Contact, Left Back
      // Phase Shift: Right leg is pi ahead of Left

      // Left Leg
      double lPhase = angle;
      v.Vector3 lTarget = _calculateRunFootPos(lPhase, isLeft: true);
      _setLimbIK(pose, 'l', 'Leg', lTarget, v.Vector3(0, 0, 1)); // Knee Bend Forward (+Z)

      // Right Leg
      double rPhase = angle + pi;
      v.Vector3 rTarget = _calculateRunFootPos(rPhase, isLeft: false);
      _setLimbIK(pose, 'r', 'Leg', rTarget, v.Vector3(0, 0, 1)); // Knee Bend Forward (+Z)

      // --- Arm Cycle (Opposite to legs) ---
      // Left Arm swings with Right Leg
      v.Vector3 lArmT = _calculateRunHandPos(rPhase, isLeft: true);
      _setLimbIK(pose, 'l', 'Arm', lArmT, v.Vector3(0, 0, -1)); // Elbow Bend Backward (-Z)

      // Right Arm swings with Left Leg
      v.Vector3 rArmT = _calculateRunHandPos(lPhase, isLeft: false);
      _setLimbIK(pose, 'r', 'Arm', rArmT, v.Vector3(0, 0, -1)); // Elbow Bend Backward (-Z)

      // Update Head
      pose.setHead(pose.neck + v.Vector3(0, -8, 0));

      frames.add(StickmanKeyframe(pose: pose, frameIndex: i));
    }
    return StickmanClip(name: "Run", keyframes: frames, fps: 30, isLooping: true);
  }

  static v.Vector3 _calculateRunFootPos(double angle, {required bool isLeft}) {
    double x = isLeft ? -4 : 4;
    double strideLen = 15.0;
    double liftHeight = 8.0;

    double cosA = cos(angle);
    double sinA = sin(angle);

    // Z: Forward/Back motion (Sin wave)
    // +Z is Forward.
    // When sin > 0 (0 to pi), foot moves Back (Stance phase) relative to hip?
    // No, if running forward, foot moves BACK relative to body during contact.
    // Stance: Z goes + to -
    // Swing: Z goes - to +

    double z = -sinA * strideLen;

    // Y: Up/Down.
    // Contact phase (approx sin > -0.5 to 0.5? No, simpler:)
    // Lift foot when moving forward (Swing)
    double y = 25.0; // Ground
    if (sinA < 0) { // Swing phase (moving forward)
       y -= sin(angle * 1) * liftHeight * -1.0; // Arch up
       y = min(25.0, y);
    }

    return v.Vector3(x, y, z);
  }

  static v.Vector3 _calculateRunHandPos(double angle, {required bool isLeft}) {
    double x = isLeft ? -8 : 8;
    // Arms swing opposite to leg (passed in phase is leg phase)
    // Arm swings forward when leg moves back (Stance)

    double swing = sin(angle) * 12.0;
    double z = swing;
    double y = -5.0 + abs(cos(angle)) * 2; // Slight bob

    // Relative to Neck (0, -15, 0)
    // Absolute position:
    return v.Vector3(0, -15, 0) + v.Vector3(x, 15 + y, z);
  }

  static double abs(double v) => v > 0 ? v : -v;

  // --- 2. JUMP ANIMATION (Fixed Lengths) ---
  static StickmanClip generateJump(StickmanSkeleton? style) {
    List<StickmanKeyframe> frames = [];
    int totalFrames = 30;

    for (int i = 0; i < totalFrames; i++) {
      double t = i / totalFrames;
      StickmanSkeleton pose = StickmanSkeleton();
      _applyStyle(pose, style);

      // Phases: 0.0-0.3 (Squat), 0.3-0.5 (Launch), 0.5-0.8 (Air), 0.8-1.0 (Land)
      double hipY = 0;
      double kneeBendZ = 1.0; // Forward

      if (t < 0.2) { // Squat
         hipY = _lerp(0, 15, t/0.2);
      } else if (t < 0.5) { // Up
         hipY = _lerp(15, -20, (t-0.2)/0.3);
      } else if (t < 0.8) { // Down
         hipY = _lerp(-20, 0, (t-0.5)/0.3);
      } else { // Recover
         hipY = _lerp(0, 0, (t-0.8)/0.2);
      }

      pose.hip.y = hipY;
      pose.neck.setValues(0, -15 + hipY, 0);

      // Feet planted (until jump)
      double footY = 25;
      if (t > 0.3 && t < 0.8) footY = hipY + 25 - 5; // Lift feet in air

      _setLimbIK(pose, 'l', 'Leg', v.Vector3(-4, footY, 0), v.Vector3(0,0,1));
      _setLimbIK(pose, 'r', 'Leg', v.Vector3(4, footY, 0), v.Vector3(0,0,1));

      // Arms swing
      double armZ = -5;
      double armY = 0;
      if (t < 0.2) { armZ = -10; armY = 5; } // Back
      else if (t < 0.5) { armZ = 15; armY = -15; } // Up!
      else { armZ = 0; armY = 0; }

      _setLimbIK(pose, 'l', 'Arm', pose.neck + v.Vector3(-8, 10+armY, armZ), v.Vector3(0,0,-1));
      _setLimbIK(pose, 'r', 'Arm', pose.neck + v.Vector3(8, 10+armY, armZ), v.Vector3(0,0,-1));

      pose.setHead(pose.neck + v.Vector3(0,-8,0));
      frames.add(StickmanKeyframe(pose: pose, frameIndex: i));
    }
    return StickmanClip(name: "Jump", keyframes: frames, fps: 30, isLooping: false);
  }

  // --- 3. KICK ANIMATION ---
  static StickmanClip generateKick(StickmanSkeleton? style) {
    List<StickmanKeyframe> frames = [];
    int totalFrames = 30;

    for (int i = 0; i < totalFrames; i++) {
      double t = i / totalFrames;
      StickmanSkeleton pose = StickmanSkeleton();
      _applyStyle(pose, style);

      // Stance
      v.Vector3 hip = v.Vector3(0, 0, 0);
      v.Vector3 lFoot = v.Vector3(-5, 25, 5);
      v.Vector3 rFoot = v.Vector3(5, 25, -5);

      if (t < 0.3) { // Chamber
         double pt = t/0.3;
         hip.x = _lerp(0, -5, pt);
         rFoot = v.Vector3(5, _lerp(25, 10, pt), _lerp(-5, 5, pt)); // Lift
      } else if (t < 0.6) { // Kick
         double pt = (t-0.3)/0.3;
         hip.x = -5;
         // High kick
         rFoot = v.Vector3(5, _lerp(10, -5, pt), _lerp(5, 20, pt));
      } else { // Return
         double pt = (t-0.6)/0.4;
         hip.x = _lerp(-5, 0, pt);
         rFoot = v.Vector3(5, _lerp(-5, 25, pt), _lerp(20, -5, pt));
      }

      pose.hip = hip;
      pose.neck.setValues(0, -15 + hip.y, 0);

      _setLimbIK(pose, 'l', 'Leg', lFoot, v.Vector3(0,0,1));
      // Right leg kicks forward (+Z)
      _setLimbIK(pose, 'r', 'Leg', rFoot, v.Vector3(0,0,1));

      // Guard Arms
      _setLimbIK(pose, 'l', 'Arm', pose.neck + v.Vector3(-8, 5, 5), v.Vector3(0,0,-1));
      _setLimbIK(pose, 'r', 'Arm', pose.neck + v.Vector3(8, 5, -5), v.Vector3(0,0,-1));

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
