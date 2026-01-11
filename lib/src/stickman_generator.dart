import 'dart:math';
import 'package:vector_math/vector_math_64.dart' as v;
import 'stickman_skeleton.dart';
import 'stickman_animation.dart';

class StickmanGenerator {

  // --- 1. MARATHON RUN (Efficient, Steady) ---
  static StickmanClip generateRun() {
    List<StickmanKeyframe> frames = [];
    int totalFrames = 26; // Slightly slower, steady rhythm

    for (int i = 0; i < totalFrames; i++) {
      double t = i / totalFrames;
      double angle = t * 2 * pi;

      StickmanSkeleton pose = StickmanSkeleton();

      // A. Hips: Very steady, less bounce than a sprint
      pose.hip.y = cos(angle * 2) * 1.5;

      // B. Spine: Slight forward lean (endurance posture), not extreme
      pose.neck.setValues(0, -25 + pose.hip.y, 3); // Z=3 is slight lean

      // C. Arms: "Low Carry" - Arms held lower, moving efficiently
      // Left Arm
      _setMarathonArm(pose, isLeft: true, angle: angle);
      // Right Arm (Phase Offset)
      _setMarathonArm(pose, isLeft: false, angle: angle + pi);

      // D. Legs: Efficient stride, heel strike, roll off toe
      // Left Leg
      _setMarathonLeg(pose, isLeft: true, angle: angle);
      // Right Leg (Phase Offset)
      _setMarathonLeg(pose, isLeft: false, angle: angle + pi);

      frames.add(StickmanKeyframe(pose: pose, frameIndex: i));
    }
    return StickmanClip(name: "Marathon", keyframes: frames, fps: 30, isLooping: true);
  }

  // --- 2. ROUNDHOUSE KICK (Rotational & Balanced) ---
  static StickmanClip generateKick() {
    List<StickmanKeyframe> frames = [];
    int totalFrames = 34;

    // Stance
    StickmanSkeleton stance = StickmanSkeleton();
    stance.lFoot.z = 5; stance.rFoot.z = -5; // Combat stance
    stance.lHand.setValues(-5, -15, 8); stance.rHand.setValues(5, -15, 5);

    for (int i = 0; i < totalFrames; i++) {
      double t = i / totalFrames;
      StickmanSkeleton pose = stance.clone();

      if (t < 0.3) {
        // PHASE 1: CHAMBER & WIND UP (0-30%)
        double subT = t / 0.3;

        // Pivot on Left Leg (Turn heel)
        pose.lFoot.x = _lerp(0, -2, subT);

        // Lean Torso Back/Left to counterbalance
        pose.hip.x = _lerp(0, -8, subT);
        pose.neck.x = _lerp(0, -20, subT); // Significant lean back
        pose.neck.z = _lerp(0, -5, subT);

        // Lift Right Knee (Chambering to the side)
        pose.rKnee.setValues(10, 0, 0); // Lifted out to side
        pose.rFoot.setValues(5, 5, -5); // Tucked behind knee

        // Hands guard face
        pose.rHand.setValues(5, -15, 0);

      } else if (t < 0.5) {
        // PHASE 2: EXTENSION (Snap) (30-50%)
        double subT = (t - 0.3) / 0.2;

        // Max Lean
        pose.hip.x = -8;
        pose.neck.x = -22;

        // Swing Leg in Arc
        // Calculate arc from Side(0) to Front-Left(Target)
        double kickAngle = _lerp(0, pi * 0.7, subT);
        double radius = 24.0;

        // Hip is pivot point
        double kX = cos(kickAngle) * 10;
        double kZ = sin(kickAngle) * 10;

        // Knee is extended
        pose.rKnee.setValues(5 + kX, -15, 5 + kZ);

        // Foot snaps out (Full extension)
        pose.rFoot.setValues(5 + kX * 2.2, -22, 5 + kZ * 2.2);

      } else if (t < 0.7) {
        // PHASE 3: RECOIL (50-70%)
        double subT = (t - 0.5) / 0.2;

        // Maintain lean (balance)
        pose.hip.x = -8;
        pose.neck.x = -20;

        // Pull foot back to knee (rapid recoil)
        pose.rKnee.setValues(10, -10, 5); // Knee stays up slightly
        pose.rFoot = _lerpVector(pose.rFoot, v.Vector3(5, 0, 0), subT);

      } else {
        // PHASE 4: LANDING (70-100%)
        double subT = (t - 0.7) / 0.3;

        // Return body to upright
        pose.hip.x = _lerp(-8, 0, subT);
        pose.neck.x = _lerp(-20, 0, subT);

        // Place foot down
        v.Vector3 footStart = v.Vector3(5, 0, 0);
        pose.rKnee = _lerpVector(v.Vector3(10, -10, 5), v.Vector3(5, 12, 0), subT);
        pose.rFoot = _lerpVector(footStart, v.Vector3(5, 24, 0), subT);
      }
      frames.add(StickmanKeyframe(pose: pose, frameIndex: i));
    }
    return StickmanClip(name: "Roundhouse", keyframes: frames, fps: 30, isLooping: false);
  }

  // --- 3. SQUAT JUMP (No high arms) ---
  static StickmanClip generateJump() {
    List<StickmanKeyframe> frames = [];
    int totalFrames = 30;

    for (int i = 0; i < totalFrames; i++) {
      double t = i / totalFrames;
      StickmanSkeleton pose = StickmanSkeleton();

      // PHYSICS: Height Parabola
      double airTime = 0.0;
      if (t > 0.3 && t < 0.8) {
         double airT = (t - 0.3) / 0.5;
         airTime = 4 * airT * (1 - airT);
      }
      double jumpY = airTime * 35.0;

      if (t < 0.3) {
        // PHASE 1: DEEP SQUAT (Anticipation)
        double subT = t / 0.3;
        double squash = sin(subT * pi) * 12; // Deeper squat (12 units)

        pose.hip.y += squash;
        pose.neck.y += squash + 2;

        // Arms: "Small pulling elbow back"
        // Move elbows back/up, hands stay low/near hips
        double armPull = sin(subT * pi) * 10;
        pose.lElbow.z = -armPull; pose.lHand.setValues(-8, pose.neck.y + 10, -5);
        pose.rElbow.z = -armPull; pose.rHand.setValues(8, pose.neck.y + 10, -5);

        // Knees out
        pose.lKnee.x -= 3 * subT;
        pose.rKnee.x += 3 * subT;

      } else if (t < 0.5) {
        // PHASE 2: LAUNCH (Upward)
        pose.hip.y -= jumpY;
        pose.neck.y = pose.hip.y - 25;

        // Arms: Natural balance (not raising high)
        // They swing forward slightly to neutral, but stay below shoulders
        pose.lElbow.setValues(-8, pose.neck.y + 15, 5);
        pose.lHand.setValues(-8, pose.neck.y + 25, 10); // Waist height
        pose.rElbow.setValues(8, pose.neck.y + 15, 5);
        pose.rHand.setValues(8, pose.neck.y + 25, 10);

        // Legs Extend fully
        pose.lKnee.y = pose.hip.y + 20; pose.lFoot.y = pose.hip.y + 35;
        pose.rKnee.y = pose.hip.y + 20; pose.rFoot.y = pose.hip.y + 35;

      } else if (t < 0.8) {
        // PHASE 3: FALL
        pose.hip.y -= jumpY;
        pose.neck.y = pose.hip.y - 25;

        // Arms stabilize
        pose.lHand.y = pose.neck.y + 20;
        pose.rHand.y = pose.neck.y + 20;

        // Legs reach for ground
        pose.lFoot.y = pose.hip.y + 30;
        pose.rFoot.y = pose.hip.y + 30;

      } else {
        // PHASE 4: LANDING
        double subT = (t - 0.8) / 0.2;
        double absorb = sin(subT * pi) * 8;

        pose.hip.y += absorb;
        pose.neck.y += absorb;

        pose.lFoot.y = 24; pose.rFoot.y = 24;
      }
      frames.add(StickmanKeyframe(pose: pose, frameIndex: i));
    }
    return StickmanClip(name: "Jump", keyframes: frames, fps: 30, isLooping: false);
  }

  // --- HELPERS ---

  static void _setMarathonArm(StickmanSkeleton pose, {required bool isLeft, required double angle}) {
     // Arms are tighter to body, swing is mainly forearm
     double swing = sin(angle) * 0.6;
     v.Vector3 neck = pose.neck;
     double side = isLeft ? -6 : 6;

     // Elbow stays relatively fixed near ribcage
     v.Vector3 elbow = neck + v.Vector3(side, 12, swing * 5);
     // Hand swings up/down from elbow
     v.Vector3 hand = elbow + v.Vector3(0, 8, 8 + swing * 8);

     if(isLeft) { pose.lElbow=elbow; pose.lHand=hand; }
     else { pose.rElbow=elbow; pose.rHand=hand; }
  }

  static void _setMarathonLeg(StickmanSkeleton pose, {required bool isLeft, required double angle}) {
     double hipY = pose.hip.y;
     double side = isLeft ? -3 : 3;

     // Elliptical path for marathon (less vertical knee lift than sprint)
     double footZ = sin(angle) * 12; // Stride
     double footY = 24; // Ground

     // Lift phase (when moving forward)
     if (cos(angle) > 0) {
        footY -= sin(angle) * 4; // Low lift (efficient)
     }

     v.Vector3 hip = pose.hip + v.Vector3(side, 0, 0);
     v.Vector3 foot = v.Vector3(side, footY, footZ);

     // IK Knee
     v.Vector3 mid = (hip + foot) * 0.5;
     mid.z += 6; // Knee bend

     if(isLeft) { pose.lKnee=mid; pose.lFoot=foot; }
     else { pose.rKnee=mid; pose.rFoot=foot; }
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
  static v.Vector3 _lerpVector(v.Vector3 a, v.Vector3 b, double t) => v.Vector3(_lerp(a.x,b.x,t), _lerp(a.y,b.y,t), _lerp(a.z,b.z,t));

  static StickmanClip generateEmpty() {
    List<StickmanKeyframe> frames = [];
    for(int i=0; i<30; i++) frames.add(StickmanKeyframe(pose: StickmanSkeleton(), frameIndex: i));
    return StickmanClip(name: "Custom", keyframes: frames, fps: 30, isLooping: true);
  }
}
