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

  // Helper to attach Head to Neck (if not manually positioned)
  static void _updateHead(StickmanSkeleton pose) {
     if(pose.head != null) {
       // Default head offset from neck is (0, -8, 0)
       pose.setHead(pose.neck + v.Vector3(0, -7.3, 0)); // Approx distance
     }
  }

  // --- 1. REFINED MARATHON RUN (Organic & Fluid) ---
  static StickmanClip generateRun(StickmanSkeleton? style) {
    List<StickmanKeyframe> frames = [];
    int totalFrames = 24;

    for (int i = 0; i < totalFrames; i++) {
      double t = i / totalFrames;
      double angle = t * 2 * pi;

      StickmanSkeleton pose = StickmanSkeleton();
      _applyStyle(pose, style);

      // A. Hips & Spine Dynamics
      // vertical bounce (lowest when foot plants)
      pose.hip.y = cos(angle * 2) * 1.5;

      // Hip Twist: As right leg goes forward, rotate hips left (Yaw)
      double hipTwist = sin(angle) * 0.15;
      _rotateY(pose.hip, hipTwist);

      // Spine Counter-Twist: Shoulders rotate OPPOSITE to hips
      pose.neck.setValues(0, -25 + pose.hip.y, 4); // Forward lean Z=4
      _rotateY(pose.neck, -hipTwist * 1.5); // Counter-rotate neck

      // B. Arms (Active Swing)
      // Left Arm (Phase 0)
      _setActiveArm(pose, isLeft: true, angle: angle);
      // Right Arm (Phase PI)
      _setActiveArm(pose, isLeft: false, angle: angle + pi);

      // C. Legs (Smooth Arc)
      // Left Leg
      _setSmoothLeg(pose, isLeft: true, angle: angle);
      // Right Leg
      _setSmoothLeg(pose, isLeft: false, angle: angle + pi);

      _updateHead(pose);

      frames.add(StickmanKeyframe(pose: pose, frameIndex: i));
    }
    return StickmanClip(name: "Marathon", keyframes: frames, fps: 30, isLooping: true);
  }

  // --- 2. ROUNDHOUSE KICK (Fixed Head & Knees) ---
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
      _applyStyle(pose, style);

      if (t < 0.3) {
        // CHAMBER
        double subT = t / 0.3;
        pose.lFoot.x = _lerp(0, -2, subT);
        pose.hip.x = _lerp(0, -8, subT);

        // HEAD FIX: Counter-lean. Body leans back (-20).
        pose.neck.x = _lerp(0, -10, subT);
        pose.neck.z = _lerp(0, -2, subT);
        // Head explicit placement (Gaze Stability)
        // Keep Head X closer to 0 than Neck X
        if(pose.head != null) {
           pose.setHead(v.Vector3(pose.neck.x * 0.5, pose.neck.y - 8, 0));
        }

        // KNEE FIX: Relative to Hip
        // Original: pose.rKnee.setValues(10, 0, 0) -> Absolute 10
        // New: Hip is at -8. Knee should be at Hip + Offset(18, 0, 0) to reach 10?
        // No, Chamber position: Knee lifted out to side.
        // Hip is at (-8, 0, 0).
        // Chamber Knee at roughly (2, 0, 0) World (10 units right of hip)
        pose.rKnee = pose.hip + v.Vector3(10, 0, 0);

        pose.rFoot.setValues(pose.rKnee.x - 5, pose.rKnee.y + 5, pose.rKnee.z - 5); // Tucked behind knee relative
        pose.rHand.setValues(5, -15, 0);

      } else if (t < 0.5) {
        // EXTENSION
        double subT = (t - 0.3) / 0.2;
        pose.hip.x = -8;

        pose.neck.x = -12;
        if(pose.head != null) pose.setHead(v.Vector3(pose.neck.x * 0.5, pose.neck.y - 8, 0));

        // Kick Arc
        double kickAngle = _lerp(0, pi * 0.7, subT);
        double kX = cos(kickAngle) * 10;
        double kZ = sin(kickAngle) * 10;

        // Knee Relative to Hip
        // Hip at -8.
        pose.rKnee = pose.hip + v.Vector3(13 + kX, -15, 5 + kZ);

        // Foot snaps out
        pose.rFoot = pose.rKnee + v.Vector3(kX * 2.2, -7, kZ * 2.2);

      } else if (t < 0.7) {
        // RECOIL
        double subT = (t - 0.5) / 0.2;
        pose.hip.x = -8;
        pose.neck.x = -12;
        if(pose.head != null) pose.setHead(v.Vector3(pose.neck.x * 0.5, pose.neck.y - 8, 0));

        pose.rKnee = pose.hip + v.Vector3(18, -10, 5);
        pose.rFoot = _lerpVector(pose.rFoot, pose.rKnee + v.Vector3(-5, 10, -5), subT);

      } else {
        // RETURN
        double subT = (t - 0.7) / 0.3;
        pose.hip.x = _lerp(-8, 0, subT);
        pose.neck.x = _lerp(-12, 0, subT);
        _updateHead(pose); // Return to normal

        v.Vector3 kneeStart = pose.hip + v.Vector3(18, -10, 5); // From Recoil
        // Return to stance default (relative to hip)
        // Stance hip is 0?
        // Wait, stance cloned hip might be default (1,0,0).
        // Let's assume stance hip is (0,0,0) offset for calculation simplicity relative to animation.
        // Actually, stickman default hip is (1,0,0).
        // Stance rFoot is (-5).

        pose.rKnee = _lerpVector(kneeStart, v.Vector3(5, 12, 0), subT);
        pose.rFoot = _lerpVector(pose.rFoot, v.Vector3(5, 24, 0), subT);
      }
      frames.add(StickmanKeyframe(pose: pose, frameIndex: i));
    }
    return StickmanClip(name: "Roundhouse", keyframes: frames, fps: 30, isLooping: false);
  }

  // --- 3. SQUAT JUMP (Fixed Head & Knees) ---
  static StickmanClip generateJump(StickmanSkeleton? style) {
    List<StickmanKeyframe> frames = [];
    int totalFrames = 30;

    // Defaults for Relative Calculation
    // Hip (1, 0, 0)
    // lKnee (-4.1, 11.8, 0) -> Rel: (-5.1, 11.8, 0)
    // rKnee (5.0, 12.0, 0)  -> Rel: (4.0, 12.0, 0)
    // lElbow (-6.1, -7.2, 0) -> Rel to Neck(0, -14.7, 0): (-6.1, 7.5, 0)

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

      if (t < 0.3) {
        // SQUAT
        double subT = t / 0.3;
        double squash = sin(subT * pi) * 12;

        pose.hip.y += squash;
        // Spine Rotation
        double lean = squash * 0.5;
        pose.neck.setValues(0, pose.hip.y - 25 + (squash * 0.5), lean);

        // Arms back (Relative to Neck)
        double armPull = sin(subT * pi) * 10;
        pose.lElbow = pose.neck + v.Vector3(-6, 7.5, -armPull);
        pose.lHand.setValues(-8, pose.neck.y + 10, -5);
        pose.rElbow = pose.neck + v.Vector3(6, 7.5, -armPull);
        pose.rHand.setValues(8, pose.neck.y + 10, -5);

        // Knees out (Relative to Hip)
        // Default Knee Y is 12 relative to hip(0).
        // Squash means Hip moves down (Y increases). Knees stay on ground logic?
        // Wait, Feet stay on ground. Knees bend.
        // If Hip Y moves from 0 to 12. Feet at 24.
        // Distance Hip->Foot is 12. (Half of 24).
        // Knee height (Y) should be halfway + bend offset.
        // Knee Y = (HipY + FootY) / 2 = (12+24)/2 = 18.
        // Default Knee Y was 12 (relative to Hip 0).
        // So Knee Y moves from 12 to 18.
        // pose.hip.y IS the hip Y.
        double kneeY = (pose.hip.y + 24) * 0.5;

        pose.lKnee = v.Vector3(-4.1 - (3 * subT), kneeY, 0);
        pose.rKnee = v.Vector3(5.0 + (3 * subT), kneeY, 0);

      } else if (t < 0.5) {
        // LAUNCH
        pose.hip.y -= jumpY;
        pose.neck.setValues(0, pose.hip.y - 25, 0);

        pose.lElbow = pose.neck + v.Vector3(-6, 7.5, 5);
        pose.lHand.setValues(-8, pose.neck.y + 25, 10);
        pose.rElbow = pose.neck + v.Vector3(6, 7.5, 5);
        pose.rHand.setValues(8, pose.neck.y + 25, 10);

        // Legs Extend
        pose.lKnee.y = pose.hip.y + 20; pose.lFoot.y = pose.hip.y + 35;
        pose.rKnee.y = pose.hip.y + 20; pose.rFoot.y = pose.hip.y + 35;

      } else if (t < 0.8) {
        // FALL
        pose.hip.y -= jumpY;
        pose.neck.setValues(0, pose.hip.y - 25, 0);

        pose.lElbow = pose.neck + v.Vector3(-6, 7.5, 0);
        pose.rElbow = pose.neck + v.Vector3(6, 7.5, 0);
        pose.lHand.y = pose.neck.y + 20; pose.rHand.y = pose.neck.y + 20;

        pose.lKnee.y = pose.hip.y + 15;
        pose.rKnee.y = pose.hip.y + 15;
        pose.lFoot.y = pose.hip.y + 30; pose.rFoot.y = pose.hip.y + 30;

      } else {
        // LANDING
        double subT = (t - 0.8) / 0.2;
        double absorb = sin(subT * pi) * 8;
        pose.hip.y += absorb;
        pose.neck.setValues(0, pose.hip.y - 25 + (absorb*0.5), absorb * 0.5);

        // Arms
        pose.lElbow = pose.neck + v.Vector3(-6, 7.5, 0);
        pose.rElbow = pose.neck + v.Vector3(6, 7.5, 0);
        pose.lHand.setValues(-8, pose.neck.y + 20, 0);
        pose.rHand.setValues(8, pose.neck.y + 20, 0);

        // Knees Absorb
        double kneeY = (pose.hip.y + 24) * 0.5;
        pose.lKnee.y = kneeY; pose.rKnee.y = kneeY;
        pose.lFoot.y = 24; pose.rFoot.y = 24;
      }

      _updateHead(pose);
      frames.add(StickmanKeyframe(pose: pose, frameIndex: i));
    }
    return StickmanClip(name: "Jump", keyframes: frames, fps: 30, isLooping: false);
  }

  // --- HELPERS FOR REFINED MOVEMENT ---

  static void _rotateY(v.Vector3 vec, double angle) {
    double cosA = cos(angle);
    double sinA = sin(angle);
    double x = vec.x;
    double z = vec.z;
    vec.x = x * cosA + z * sinA;
    vec.z = -x * sinA + z * cosA;
  }

  static void _setSmoothLeg(StickmanSkeleton pose, {required bool isLeft, required double angle}) {
     double side = isLeft ? -3 : 3;

     // 1. Stride (Forward/Back) - Sine wave
     double stride = sin(angle) * 13;

     // 2. Lift (Up/Down) - "Egg" shape trajectory
     // We want the foot low during the "back" phase (push off)
     // And high during the "forward" phase (swing)
     double cosVal = cos(angle); // +1 is Forward Swing, -1 is Back Push
     double footY = 24;

     // Smooth Lift Logic:
     if (cosVal > 0) {
        // Swing Phase: Lift foot high to clear ground
        footY -= cosVal * 5.0;
        // Add extra "Knee Drive" pop at the peak
        footY -= max(0.0, sin(angle + pi/4)) * 2;
     } else {
        // Stance/Push Phase: Keep foot flat/low
        footY += cosVal * 0.5; // Slight dip
     }

     // Apply rotation to start/end points based on Hip Twist (approx)
     v.Vector3 hipPos = pose.hip + v.Vector3(side, 0, 0);
     v.Vector3 footPos = v.Vector3(side, footY, stride);

     // IK Knee Solver
     v.Vector3 mid = (hipPos + footPos) * 0.5;
     mid.z += 8; // Knee bends forward

     if(isLeft) { pose.lKnee=mid; pose.lFoot=footPos; }
     else { pose.rKnee=mid; pose.rFoot=footPos; }
  }

  static void _setActiveArm(StickmanSkeleton pose, {required bool isLeft, required double angle}) {
     v.Vector3 neck = pose.neck;
     double side = isLeft ? -6 : 6;

     // Swing angle
     double swing = sin(angle) * 0.7;

     // DYNAMIC ELBOW:
     // When arm swings forward (swing > 0), bend elbow MORE (tuck).
     // When arm swings back (swing < 0), straighten elbow slightly.
     double elbowBendOffset = max(0.0, swing) * 4.0;

     // Elbow Position
     // Note: Y is Down.
     v.Vector3 elbow = neck + v.Vector3(side, 10 - (elbowBendOffset*0.2), swing * 8);

     // Hand Position
     // Forearm swings relative to elbow
     v.Vector3 hand = elbow + v.Vector3(0, 10, 5 + swing * 5 + elbowBendOffset);

     if(isLeft) { pose.lElbow=elbow; pose.lHand=hand; }
     else { pose.rElbow=elbow; pose.rHand=hand; }
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
