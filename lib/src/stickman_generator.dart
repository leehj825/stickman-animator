import 'dart:math';
import 'package:vector_math/vector_math_64.dart' as v;
import 'stickman_skeleton.dart';
import 'stickman_animation.dart';

class StickmanGenerator {

  // Apply style helper
  static void _applyStyle(StickmanSkeleton pose, StickmanSkeleton? style) {
    if (style != null) {
      pose.headRadius = style.headRadius;
      pose.strokeWidth = style.strokeWidth;
    }
  }

  // --- 1. MARATHON RUN ---
  static StickmanClip generateRun(StickmanSkeleton? style) {
    List<StickmanKeyframe> frames = [];
    int totalFrames = 26;

    for (int i = 0; i < totalFrames; i++) {
      double t = i / totalFrames;
      double angle = t * 2 * pi;

      StickmanSkeleton pose = StickmanSkeleton();
      _applyStyle(pose, style);

      // Hips & Spine
      pose.hip.y = cos(angle * 2) * 1.5;
      pose.neck.setValues(0, -25 + pose.hip.y, 3); // Z=3 slight lean

      // Arms & Legs (Same Marathon Logic)
      _setMarathonArm(pose, isLeft: true, angle: angle);
      _setMarathonArm(pose, isLeft: false, angle: angle + pi);
      _setMarathonLeg(pose, isLeft: true, angle: angle);
      _setMarathonLeg(pose, isLeft: false, angle: angle + pi);

      frames.add(StickmanKeyframe(pose: pose, frameIndex: i));
    }
    return StickmanClip(name: "Marathon", keyframes: frames, fps: 30, isLooping: true);
  }

  // --- 2. ROUNDHOUSE KICK (Fixed Head) ---
  static StickmanClip generateKick(StickmanSkeleton? style) {
    List<StickmanKeyframe> frames = [];
    int totalFrames = 34;

    StickmanSkeleton stance = StickmanSkeleton();
    stance.lFoot.z = 5; stance.rFoot.z = -5;
    stance.lHand.setValues(-5, -15, 8); stance.rHand.setValues(5, -15, 5);
    _applyStyle(stance, style);

    for (int i = 0; i < totalFrames; i++) {
      double t = i / totalFrames;
      StickmanSkeleton pose = stance.clone();
      // Clone doesn't always copy style if not implemented deep, so safe re-apply:
      _applyStyle(pose, style);

      if (t < 0.3) {
        // CHAMBER
        double subT = t / 0.3;
        pose.lFoot.x = _lerp(0, -2, subT);
        pose.hip.x = _lerp(0, -8, subT);

        // HEAD FIX: Counter-lean. Body leans back (-20), Head leans less (-10)
        pose.neck.x = _lerp(0, -10, subT);
        pose.neck.z = _lerp(0, -2, subT);

        pose.rKnee.setValues(10, 0, 0);
        pose.rFoot.setValues(5, 5, -5);
        pose.rHand.setValues(5, -15, 0);

      } else if (t < 0.5) {
        // EXTENSION
        double subT = (t - 0.3) / 0.2;
        pose.hip.x = -8;

        // HEAD FIX: Keep head upright-ish even during max lean
        pose.neck.x = -12; // Body is usually -22 here. -12 keeps head forward.

        // Kick Arc
        double kickAngle = _lerp(0, pi * 0.7, subT);
        double kX = cos(kickAngle) * 10;
        double kZ = sin(kickAngle) * 10;
        pose.rKnee.setValues(5 + kX, -15, 5 + kZ);
        pose.rFoot.setValues(5 + kX * 2.2, -22, 5 + kZ * 2.2);

      } else if (t < 0.7) {
        // RECOIL
        double subT = (t - 0.5) / 0.2;
        pose.hip.x = -8;
        pose.neck.x = -12; // Maintain fix
        pose.rKnee.setValues(10, -10, 5);
        pose.rFoot = _lerpVector(pose.rFoot, v.Vector3(5, 0, 0), subT);

      } else {
        // RETURN
        double subT = (t - 0.7) / 0.3;
        pose.hip.x = _lerp(-8, 0, subT);
        pose.neck.x = _lerp(-12, 0, subT); // Return from -12
        v.Vector3 footStart = v.Vector3(5, 0, 0);
        pose.rKnee = _lerpVector(v.Vector3(10, -10, 5), v.Vector3(5, 12, 0), subT);
        pose.rFoot = _lerpVector(footStart, v.Vector3(5, 24, 0), subT);
      }
      frames.add(StickmanKeyframe(pose: pose, frameIndex: i));
    }
    return StickmanClip(name: "Roundhouse", keyframes: frames, fps: 30, isLooping: false);
  }

  // --- 3. SQUAT JUMP (Fixed Head) ---
  static StickmanClip generateJump(StickmanSkeleton? style) {
    List<StickmanKeyframe> frames = [];
    int totalFrames = 30;

    for (int i = 0; i < totalFrames; i++) {
      double t = i / totalFrames;
      StickmanSkeleton pose = StickmanSkeleton();
      _applyStyle(pose, style);

      double airTime = 0.0;
      if (t > 0.3 && t < 0.8) {
         double airT = (t - 0.3) / 0.5;
         airTime = 4 * airT * (1 - airT);
      }
      double jumpY = airTime * 35.0;

      // HEAD FIX: Maintain Spine Length ~25
      // Instead of manual neck.y setting, we calculate it relative to hip

      if (t < 0.3) {
        // SQUAT
        double subT = t / 0.3;
        double squash = sin(subT * pi) * 12;

        pose.hip.y += squash;
        // Spine Rotation: Bend forward (Z axis) instead of just shrinking Y
        double lean = squash * 0.5;
        pose.neck.setValues(0, pose.hip.y - 25 + (squash * 0.5), lean);

        // Arms back
        double armPull = sin(subT * pi) * 10;
        pose.lElbow.z = -armPull; pose.lHand.setValues(-8, pose.neck.y + 10, -5);
        pose.rElbow.z = -armPull; pose.rHand.setValues(8, pose.neck.y + 10, -5);
        pose.lKnee.x -= 3 * subT; pose.rKnee.x += 3 * subT;

      } else if (t < 0.5) {
        // LAUNCH
        pose.hip.y -= jumpY;
        pose.neck.setValues(0, pose.hip.y - 25, 0); // Straight spine

        pose.lElbow.setValues(-8, pose.neck.y + 15, 5);
        pose.lHand.setValues(-8, pose.neck.y + 25, 10);
        pose.rElbow.setValues(8, pose.neck.y + 15, 5);
        pose.rHand.setValues(8, pose.neck.y + 25, 10);

        pose.lKnee.y = pose.hip.y + 20; pose.lFoot.y = pose.hip.y + 35;
        pose.rKnee.y = pose.hip.y + 20; pose.rFoot.y = pose.hip.y + 35;

      } else if (t < 0.8) {
        // FALL
        pose.hip.y -= jumpY;
        pose.neck.setValues(0, pose.hip.y - 25, 0);

        pose.lHand.y = pose.neck.y + 20; pose.rHand.y = pose.neck.y + 20;
        pose.lFoot.y = pose.hip.y + 30; pose.rFoot.y = pose.hip.y + 30;

      } else {
        // LANDING
        double subT = (t - 0.8) / 0.2;
        double absorb = sin(subT * pi) * 8;
        pose.hip.y += absorb;
        // Spine Flex
        pose.neck.setValues(0, pose.hip.y - 25 + (absorb*0.5), absorb * 0.5);
        pose.lFoot.y = 24; pose.rFoot.y = 24;
      }
      frames.add(StickmanKeyframe(pose: pose, frameIndex: i));
    }
    return StickmanClip(name: "Jump", keyframes: frames, fps: 30, isLooping: false);
  }

  // --- HELPERS (Keep existing) ---
  static void _setMarathonArm(StickmanSkeleton pose, {required bool isLeft, required double angle}) {
     double swing = sin(angle) * 0.6;
     v.Vector3 neck = pose.neck;
     double side = isLeft ? -6 : 6;
     v.Vector3 elbow = neck + v.Vector3(side, 12, swing * 5);
     v.Vector3 hand = elbow + v.Vector3(0, 8, 8 + swing * 8);
     if(isLeft) { pose.lElbow=elbow; pose.lHand=hand; }
     else { pose.rElbow=elbow; pose.rHand=hand; }
  }

  static void _setMarathonLeg(StickmanSkeleton pose, {required bool isLeft, required double angle}) {
     double hipY = pose.hip.y;
     double side = isLeft ? -3 : 3;
     double footZ = sin(angle) * 12;
     double footY = 24;
     if (cos(angle) > 0) footY -= sin(angle) * 4;
     v.Vector3 hip = pose.hip + v.Vector3(side, 0, 0);
     v.Vector3 foot = v.Vector3(side, footY, footZ);
     v.Vector3 mid = (hip + foot) * 0.5;
     mid.z += 6;
     if(isLeft) { pose.lKnee=mid; pose.lFoot=foot; }
     else { pose.rKnee=mid; pose.rFoot=foot; }
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
  static v.Vector3 _lerpVector(v.Vector3 a, v.Vector3 b, double t) => v.Vector3(_lerp(a.x,b.x,t), _lerp(a.y,b.y,t), _lerp(a.z,b.z,t));

  static StickmanClip generateEmpty(StickmanSkeleton? style) {
    List<StickmanKeyframe> frames = [];
    for(int i=0; i<30; i++) {
        StickmanSkeleton p = StickmanSkeleton();
        _applyStyle(p, style);
        frames.add(StickmanKeyframe(pose: p, frameIndex: i));
    }
    return StickmanClip(name: "Custom", keyframes: frames, fps: 30, isLooping: true);
  }
}
