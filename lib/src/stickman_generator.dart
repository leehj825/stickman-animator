import 'dart:math';
import 'package:vector_math/vector_math_64.dart' as v;
import 'stickman_skeleton.dart';
import 'stickman_animation.dart';

class StickmanGenerator {

  // --- 1. THE "REALISTIC" RUN (Rotary Gallop) ---
  static StickmanClip generateRun() {
    List<StickmanKeyframe> frames = [];
    int totalFrames = 24; // Standard cycle length

    for (int i = 0; i < totalFrames; i++) {
      double t = i / totalFrames; // 0.0 to 1.0
      double angle = t * 2 * pi;

      StickmanSkeleton pose = StickmanSkeleton();

      // A. Hips (The Engine)
      // Bob: Up/Down twice per cycle (lowest when foot plants)
      double bob = cos(angle * 2) * 2.0;
      // Twist: Rotate hips slightly to follow the forward leg
      double twist = sin(angle) * 0.1;

      pose.hip.setValues(0, 0 + bob, 0);

      // B. Spine (The Lean)
      // Lean forward for momentum
      pose.neck.setValues(0, -25 + bob, 5);

      // Apply Hip Twist to Neck (Counter-rotation looks better, but simple follow is fine)
      _rotateY(pose.neck, twist * 0.5);

      // C. Legs (The Wheel)
      // Right Leg (Phase 0)
      _applyLegGallop(pose, isLeft: false, progress: t);
      // Left Leg (Phase 0.5 - Opposite)
      _applyLegGallop(pose, isLeft: true, progress: (t + 0.5) % 1.0);

      // D. Arms (The Counter-Balance)
      // Arms swing opposite to legs.
      // Right Arm swings with Left Leg (Phase 0.5)
      _applyArmSwing(pose, isLeft: false, progress: (t + 0.5) % 1.0);
      // Left Arm swings with Right Leg (Phase 0)
      _applyArmSwing(pose, isLeft: true, progress: t);

      frames.add(StickmanKeyframe(pose: pose, frameIndex: i));
    }
    return StickmanClip(name: "Run", keyframes: frames, fps: 30, isLooping: true);
  }

  // --- 2. THE "POWER" KICK (4-Stage Linear) ---
  static StickmanClip generateKick() {
    List<StickmanKeyframe> frames = [];
    int totalFrames = 30; // 1 second kick

    // Base Stance
    StickmanSkeleton stance = StickmanSkeleton();
    _applyLegStance(stance, isLeft: true, xOffset: -5, zOffset: 5); // Left foot forward
    _applyLegStance(stance, isLeft: false, xOffset: 5, zOffset: -5); // Right foot back
    stance.lHand.setValues(-10, -15, 10); // Guard up
    stance.rHand.setValues(10, -15, 5);

    for (int i = 0; i < totalFrames; i++) {
      double t = i / totalFrames;
      StickmanSkeleton pose = stance.clone(); // Start from stance

      // Animate Right Leg (The Kicker)
      if (t < 0.3) {
        // STAGE 1: CHAMBER (0% - 30%)
        // Lift knee high, keep foot tucked
        double subT = t / 0.3; // 0..1 for this phase

        // Shift weight to Left Leg
        pose.hip.x = _lerp(0, -5, subT);
        pose.neck.x = _lerp(0, -8, subT); // Lean away

        // Lift Right Knee
        pose.rKnee.y = _lerp(12, -5, subT);
        pose.rKnee.z = _lerp(0, 10, subT);
        pose.rFoot.setFrom(pose.rKnee + v.Vector3(0, 10, -5)); // Tucked under

      } else if (t < 0.45) {
        // STAGE 2: EXTENSION (30% - 45%)
        // Snap!
        double subT = (t - 0.3) / 0.15;

        pose.hip.x = -5;
        pose.neck.x = -12; // Lean back more

        // Knee holds position
        pose.rKnee.setValues(5, -5, 15);

        // Foot shoots out
        v.Vector3 target = v.Vector3(5, -15, 25); // Target high
        v.Vector3 start = v.Vector3(5, 5, 10);    // Tucked
        pose.rFoot = _lerpVector(start, target, subT);

      } else if (t < 0.6) {
        // STAGE 3: RECOIL (45% - 60%)
        // Pull back fast
        double subT = (t - 0.45) / 0.15;

        pose.hip.x = -5;
        pose.neck.x = -10;
        pose.rKnee.setValues(5, -5, 15);

        v.Vector3 extended = v.Vector3(5, -15, 25);
        v.Vector3 tucked = v.Vector3(5, 5, 10);
        pose.rFoot = _lerpVector(extended, tucked, subT);

      } else {
        // STAGE 4: RETURN (60% - 100%)
        // Lower leg to ground
        double subT = (t - 0.6) / 0.4;

        // Return body to center
        pose.hip.x = _lerp(-5, 0, subT);
        pose.neck.x = _lerp(-10, 0, subT);

        // Lower Knee and Foot
        v.Vector3 kneeStart = v.Vector3(5, -5, 15);
        v.Vector3 footStart = v.Vector3(5, 5, 10);

        // Interpolate back to stance positions (approx)
        pose.rKnee = _lerpVector(kneeStart, v.Vector3(5, 12, 0), subT);
        pose.rFoot = _lerpVector(footStart, v.Vector3(5, 24, 0), subT);
      }

      frames.add(StickmanKeyframe(pose: pose, frameIndex: i));
    }
    return StickmanClip(name: "Kick", keyframes: frames, fps: 30, isLooping: false);
  }

  // --- 3. THE "ATHLETIC" JUMP (Physics Arc) ---
  static StickmanClip generateJump() {
    List<StickmanKeyframe> frames = [];
    int totalFrames = 30;

    for (int i = 0; i < totalFrames; i++) {
      double t = i / totalFrames;
      StickmanSkeleton pose = StickmanSkeleton();

      // PHYSICS: Height follows a parabola (y = -4x^2 + 4x)
      double airTime = 0.0;
      if (t > 0.2 && t < 0.8) {
         double airT = (t - 0.2) / 0.6; // 0..1 in air
         airTime = 4 * airT * (1 - airT); // Parabola 0 -> 1 -> 0
      }
      double jumpY = airTime * 40.0;

      if (t < 0.2) {
        // PHASE 1: SQUAT (Anticipation)
        double subT = t / 0.2;
        double squash = sin(subT * pi) * 10; // Dip down

        pose.hip.y += squash;
        pose.neck.y += squash + 5; // Head dips more (crunch)

        // Arms swing back
        pose.lElbow.z = -10 * subT; pose.lHand.z = -20 * subT;
        pose.rElbow.z = -10 * subT; pose.rHand.z = -20 * subT;

        // Knees bend out
        pose.lKnee.x -= 2 * subT;
        pose.rKnee.x += 2 * subT;

      } else if (t < 0.5) {
        // PHASE 2: LAUNCH & TUCK (Upward)
        pose.hip.y -= jumpY;
        pose.neck.y = pose.hip.y - 25;

        // Arms fly up
        pose.lHand.y = pose.neck.y - 20;
        pose.rHand.y = pose.neck.y - 20;

        // Legs tuck up (Knees raise)
        double tuck = min(1.0, (t - 0.2) * 5); // Fast tuck
        pose.lKnee.y = pose.hip.y + 5;
        pose.rKnee.y = pose.hip.y + 5;
        pose.lFoot.y = pose.hip.y + 15;
        pose.rFoot.y = pose.hip.y + 15;

      } else if (t < 0.8) {
        // PHASE 3: FALL & EXTEND (Downward)
        pose.hip.y -= jumpY;
        pose.neck.y = pose.hip.y - 25;

        // Arms float down
        pose.lHand.y = pose.neck.y;
        pose.rHand.y = pose.neck.y;

        // Legs extend to catch ground
        pose.lKnee.y = pose.hip.y + 12;
        pose.rKnee.y = pose.hip.y + 12;
        pose.lFoot.y = pose.hip.y + 24;
        pose.rFoot.y = pose.hip.y + 24;

      } else {
        // PHASE 4: LANDING (Compress)
        double subT = (t - 0.8) / 0.2;
        double absorb = sin(subT * pi) * 8; // Dip down

        pose.hip.y += absorb;
        pose.neck.y += absorb;

        // Feet planted
        pose.lFoot.y = 24;
        pose.rFoot.y = 24;
      }

      frames.add(StickmanKeyframe(pose: pose, frameIndex: i));
    }
    return StickmanClip(name: "Jump", keyframes: frames, fps: 30, isLooping: false);
  }

  // --- 4. UTILITIES ---

  static StickmanClip generateEmpty() {
    List<StickmanKeyframe> frames = [];
    for(int i=0; i<30; i++) {
      frames.add(StickmanKeyframe(pose: StickmanSkeleton(), frameIndex: i));
    }
    return StickmanClip(name: "Custom", keyframes: frames, fps: 30, isLooping: true);
  }

  // Helper: Rotary Gallop Leg Logic
  static void _applyLegGallop(StickmanSkeleton pose, {required bool isLeft, required double progress}) {
    // progress 0.0 - 1.0
    double hipY = pose.hip.y;
    double hipZ = pose.hip.z;
    double hipX = isLeft ? -3 : 3; // Hips have slight width implicitly

    double footX = hipX;
    double footY = 0;
    double footZ = 0;

    if (progress < 0.5) {
      // CONTACT PHASE (Foot on ground, moving back relative to body)
      // Linear interpolation from Front to Back
      double t = progress / 0.5; // 0..1
      footY = 24; // Floor level (relative to root 0)
      footZ = _lerp(15, -15, t); // Stride length
    } else {
      // SWING PHASE (Foot in air, moving forward)
      // Cycloid / Arc
      double t = (progress - 0.5) / 0.5;
      footZ = _lerp(-15, 15, t);
      // Lift high in the middle
      footY = 24 - (sin(t * pi) * 15);
    }

    // Solve Knee IK (Simple Trigonometry)
    // We know Hip and Foot. Knee is in between.
    v.Vector3 hipPos = v.Vector3(hipX, hipY, hipZ) + pose.hip; // Global hip
    v.Vector3 footPos = v.Vector3(footX, footY, footZ);

    // Knee helps to bend forward usually
    v.Vector3 mid = (hipPos + footPos) * 0.5;
    mid.z += 8; // Force knee forward

    if (isLeft) {
      pose.lKnee = mid;
      pose.lFoot = footPos;
    } else {
      pose.rKnee = mid;
      pose.rFoot = footPos;
    }
  }

  static void _applyArmSwing(StickmanSkeleton pose, {required bool isLeft, required double progress}) {
    // Simple pendulum with elbow bend
    double angle = sin(progress * 2 * pi) * 0.8;

    v.Vector3 neck = pose.neck;
    double sideX = isLeft ? -6 : 6;

    // Elbow
    double elbowZ = sin(angle) * 10;
    double elbowY = cos(angle) * 10;

    v.Vector3 elbowPos = neck + v.Vector3(sideX, elbowY, elbowZ);

    // Hand (Forearm bends up slightly)
    v.Vector3 handPos = elbowPos + v.Vector3(0, 10, 5);
    // Rotate forearm based on swing
    handPos.z += sin(angle) * 5;

    if (isLeft) {
      pose.lElbow = elbowPos;
      pose.lHand = handPos;
    } else {
      pose.rElbow = elbowPos;
      pose.rHand = handPos;
    }
  }

  static void _applyLegStance(StickmanSkeleton pose, {required bool isLeft, double xOffset=0, double zOffset=0}) {
     if(isLeft) {
       pose.lKnee.add(v.Vector3(xOffset/2, 0, zOffset/2));
       pose.lFoot.add(v.Vector3(xOffset, 0, zOffset));
     } else {
       pose.rKnee.add(v.Vector3(xOffset/2, 0, zOffset/2));
       pose.rFoot.add(v.Vector3(xOffset, 0, zOffset));
     }
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  static v.Vector3 _lerpVector(v.Vector3 a, v.Vector3 b, double t) {
    return v.Vector3(
      _lerp(a.x, b.x, t),
      _lerp(a.y, b.y, t),
      _lerp(a.z, b.z, t),
    );
  }

  static void _rotateY(v.Vector3 v, double angle) {
    double cosA = cos(angle);
    double sinA = sin(angle);
    double x = v.x * cosA - v.z * sinA;
    double z = v.x * sinA + v.z * cosA;
    v.x = x;
    v.z = z;
  }
}
