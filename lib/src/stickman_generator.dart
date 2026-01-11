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

  // Helper to attach Head to Neck
  static void _updateHead(StickmanSkeleton pose) {
     if(pose.head != null) {
       // Head follows neck rotation/position
       // Default offset (0, -7.3, 0) relative to neck
       pose.setHead(pose.neck + v.Vector3(0, -7.3, 0));
     }
  }

  // --- 1. REFINED MARATHON RUN (Asymmetrical Arms) ---
  static StickmanClip generateRun(StickmanSkeleton? style) {
    List<StickmanKeyframe> frames = [];
    int totalFrames = 24;

    for (int i = 0; i < totalFrames; i++) {
      double t = i / totalFrames;
      double angle = t * 2 * pi;

      StickmanSkeleton pose = StickmanSkeleton();
      _applyStyle(pose, style);

      // A. Hips & Spine
      pose.hip.y = cos(angle * 2) * 1.5; // Bounce

      // Twist Hips
      double hipTwist = sin(angle) * 0.15;
      _rotateY(pose.hip, hipTwist);

      // Lean & Counter-Twist Spine
      pose.neck.setValues(0, -25 + pose.hip.y, 4);
      _rotateY(pose.neck, -hipTwist * 1.5);

      // B. Arms (Opposite & Biased Back)
      // Left Leg uses 'angle'. So Left Arm must be 'angle + pi'
      _setActiveArm(pose, isLeft: true, angle: angle + pi);

      // Right Leg uses 'angle + pi'. So Right Arm must be 'angle'
      _setActiveArm(pose, isLeft: false, angle: angle);

      // C. Legs
      _setSmoothLeg(pose, isLeft: true, angle: angle);
      _setSmoothLeg(pose, isLeft: false, angle: angle + pi);

      _updateHead(pose);

      frames.add(StickmanKeyframe(pose: pose, frameIndex: i));
    }
    return StickmanClip(name: "Run", keyframes: frames, fps: 30, isLooping: true);
  }

  // --- 2. ROUNDHOUSE KICK (Fixed Tracking & Height) ---
  static StickmanClip generateKick(StickmanSkeleton? style) {
    List<StickmanKeyframe> frames = [];
    int totalFrames = 34;
    const double thighLen = 13.0;
    const double shinLen = 13.0;

    // Stance
    StickmanSkeleton stance = StickmanSkeleton();
    stance.lFoot.z = 5; stance.rFoot.z = -5;
    // Arms relative to body initially (approx)
    stance.lHand.setValues(-5, -15, 8); stance.rHand.setValues(5, -15, 5);
    _applyStyle(stance, style);

    for (int i = 0; i < totalFrames; i++) {
      double t = i / totalFrames;
      StickmanSkeleton pose = stance.clone();
      _applyStyle(pose, style);

      if (t < 0.3) {
        // --- PHASE 1: CHAMBER ---
        double subT = t / 0.3;

        // Lean Back
        pose.hip.x = _lerp(0, -5, subT);
        pose.neck.x = _lerp(0, -15, subT);
        pose.neck.z = _lerp(0, -5, subT);

        // Arms Follow Body
        pose.lHand = pose.neck + v.Vector3(-8, 5, 10); // Guarding face
        pose.rHand = pose.neck + v.Vector3(8, 5, 2);   // Guarding side

        // Lift Knee (FK)
        double thighPitch = _lerp(0, -pi/2 + 0.2, subT);
        double thighYaw = _lerp(0, pi/2, subT);

        v.Vector3 kneeOffset = _sphericalToCartesian(thighLen, thighPitch, thighYaw);
        pose.rKnee = pose.hip + kneeOffset;

        // Tuck Foot
        double shinPitch = _lerp(0, pi * 0.8, subT);
        v.Vector3 footOffset = _sphericalToCartesian(shinLen, thighPitch + shinPitch, thighYaw);
        pose.rFoot = pose.rKnee + footOffset;

      } else if (t < 0.5) {
        // --- PHASE 2: EXTENSION (Snap) ---
        double subT = (t - 0.3) / 0.2;

        pose.hip.x = -5;
        pose.neck.x = -20; // More lean for high kick

        // Arms Follow Body
        pose.lHand = pose.neck + v.Vector3(-8, 5, 10);
        pose.rHand = pose.neck + v.Vector3(8, 0, 5); // Balance arm

        // Thigh
        double thighYaw = _lerp(pi/2, pi * 0.7, subT);
        // HIGHER TARGET: -pi/2 - 0.4 (Aiming up)
        double thighPitch = -pi/2 - 0.4;

        v.Vector3 kneeOffset = _sphericalToCartesian(thighLen, thighPitch, thighYaw);
        pose.rKnee = pose.hip + kneeOffset;

        // Shin Snap
        double shinPitch = _lerp(pi * 0.8, 0.0, subT);
        v.Vector3 footOffset = _sphericalToCartesian(shinLen, thighPitch + shinPitch, thighYaw);
        pose.rFoot = pose.rKnee + footOffset;

      } else if (t < 0.7) {
        // --- PHASE 3: RECOIL ---
        double subT = (t - 0.5) / 0.2;

        pose.hip.x = -5;
        pose.neck.x = -18;

        pose.lHand = pose.neck + v.Vector3(-8, 5, 10);
        pose.rHand = pose.neck + v.Vector3(8, 2, 5);

        // Keep knee up
        double thighYaw = pi * 0.7;
        double thighPitch = _lerp(-pi/2 - 0.4, -pi/4, subT); // Drop slightly

        v.Vector3 kneeOffset = _sphericalToCartesian(thighLen, thighPitch, thighYaw);
        pose.rKnee = pose.hip + kneeOffset;

        // Fold foot back
        double shinPitch = _lerp(0.0, pi * 0.9, subT);
        v.Vector3 footOffset = _sphericalToCartesian(shinLen, thighPitch + shinPitch, thighYaw);
        pose.rFoot = pose.rKnee + footOffset;

      } else {
        // --- PHASE 4: RETURN ---
        double subT = (t - 0.7) / 0.3;

        pose.hip.x = _lerp(-5, 0, subT);
        pose.neck.x = _lerp(-18, 0, subT);

        // Arms return to neutral
        pose.lHand = _lerpVector(pose.neck + v.Vector3(-8, 5, 10), pose.neck + v.Vector3(-10, 15, 0), subT);
        pose.rHand = _lerpVector(pose.neck + v.Vector3(8, 2, 5), pose.neck + v.Vector3(10, 15, 0), subT);

        // Land
        v.Vector3 landingKnee = pose.hip + v.Vector3(3, 12, 0);
        v.Vector3 landingFoot = landingKnee + v.Vector3(3, 12, 0);
        v.Vector3 recoilKnee = pose.hip + _sphericalToCartesian(thighLen, -pi/4, pi * 0.7);

        pose.rKnee = _lerpVector(recoilKnee, landingKnee, subT);
        pose.rFoot = _lerpVector(pose.rKnee + v.Vector3(0,10,0), landingFoot, subT);
      }

      // Update Head to stay balanced
      if(pose.head != null) {
         pose.setHead(pose.neck + v.Vector3(pose.neck.x * -0.2, -7.3, 0));
      }

      frames.add(StickmanKeyframe(pose: pose, frameIndex: i));
    }
    return StickmanClip(name: "Kick", keyframes: frames, fps: 30, isLooping: false);
  }

  // --- 3. SQUAT JUMP (Smoother Transition) ---
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

      if (t < 0.3) {
        // SQUAT
        double subT = t / 0.3;
        double squash = sin(subT * pi) * 12;

        pose.hip.y += squash;
        double lean = squash * 0.5;
        pose.neck.setValues(0, pose.hip.y - 25 + (squash * 0.5), lean);

        // Arms back (Relative)
        double armPull = sin(subT * pi) * 10;
        pose.lElbow = pose.neck + v.Vector3(-6, 7.5, -armPull);
        pose.lHand.setValues(-8, pose.neck.y + 10, -5);
        pose.rElbow = pose.neck + v.Vector3(6, 7.5, -armPull);
        pose.rHand.setValues(8, pose.neck.y + 10, -5);

        double kneeY = (pose.hip.y + 24) * 0.5;
        pose.lKnee = v.Vector3(-4.1 - (3 * subT), kneeY, 0);
        pose.rKnee = v.Vector3(5.0 + (3 * subT), kneeY, 0);

      } else if (t < 0.5) {
        // LAUNCH (t=0.3 to 0.5)
        pose.hip.y -= jumpY;
        pose.neck.setValues(0, pose.hip.y - 25, 0);

        // Elbows tight
        pose.lElbow = pose.neck + v.Vector3(-6, 7.5, 5);
        pose.rElbow = pose.neck + v.Vector3(6, 7.5, 5);
        // Hands low
        pose.lHand.setValues(-8, pose.neck.y + 25, 10);
        pose.rHand.setValues(8, pose.neck.y + 25, 10);

        pose.lKnee.y = pose.hip.y + 20; pose.lFoot.y = pose.hip.y + 35;
        pose.rKnee.y = pose.hip.y + 20; pose.rFoot.y = pose.hip.y + 35;

      } else if (t < 0.8) {
        // FALL (t=0.5 to 0.8)
        // Transition arms smoothly from Launch pos
        double subT = (t - 0.5) / 0.3;

        pose.hip.y -= jumpY;
        pose.neck.setValues(0, pose.hip.y - 25, 0);

        // Interpolate Elbows so they don't pop
        // Launch: Z=5. Fall Target: Z=0.
        double elbowZ = _lerp(5, 0, subT);
        pose.lElbow = pose.neck + v.Vector3(-6, 7.5, elbowZ);
        pose.rElbow = pose.neck + v.Vector3(6, 7.5, elbowZ);

        // Interpolate Hands
        // Launch: neck.y+25. Fall Target: neck.y+20.
        double handYOffset = _lerp(25, 20, subT);
        pose.lHand.y = pose.neck.y + handYOffset;
        pose.rHand.y = pose.neck.y + handYOffset;
        pose.lHand.x = -8; pose.rHand.x = 8;

        // Legs reaching
        pose.lKnee.y = pose.hip.y + 15; pose.lFoot.y = pose.hip.y + 30;
        pose.rKnee.y = pose.hip.y + 15; pose.rFoot.y = pose.hip.y + 30;

      } else {
        // LANDING
        double subT = (t - 0.8) / 0.2;
        double absorb = sin(subT * pi) * 8;
        pose.hip.y += absorb;
        pose.neck.setValues(0, pose.hip.y - 25 + (absorb*0.5), absorb * 0.5);

        pose.lHand.setValues(-8, pose.neck.y + 20, 0);
        pose.rHand.setValues(8, pose.neck.y + 20, 0);
        pose.lElbow = pose.neck + v.Vector3(-6, 7.5, 0);
        pose.rElbow = pose.neck + v.Vector3(6, 7.5, 0);

        double kneeY = (pose.hip.y + 24) * 0.5;
        pose.lKnee.y = kneeY; pose.rKnee.y = kneeY;
        pose.lFoot.y = 24; pose.rFoot.y = 24;
      }

      _updateHead(pose);
      frames.add(StickmanKeyframe(pose: pose, frameIndex: i));
    }
    return StickmanClip(name: "Jump", keyframes: frames, fps: 30, isLooping: false);
  }

  // --- HELPERS ---

  static v.Vector3 _sphericalToCartesian(double r, double pitch, double yaw) {
    // Corrected orientation assumption:
    // Pitch 0 is Down (Y+). -pi/2 is Forward (Z+).
    double y = r * cos(pitch);
    double h = r * sin(pitch);

    double z = -h * cos(yaw);
    double x = -h * sin(yaw);

    return v.Vector3(x, y, z);
  }

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
     double stride = sin(angle) * 13;
     double cosVal = cos(angle);
     double footY = 24;
     if (cosVal > 0) {
        footY -= cosVal * 5.0;
        footY -= max(0.0, sin(angle + pi/4)) * 2;
     } else {
        footY += cosVal * 0.5;
     }
     v.Vector3 hipPos = pose.hip + v.Vector3(side, 0, 0);
     v.Vector3 footPos = v.Vector3(side, footY, stride);
     v.Vector3 mid = (hipPos + footPos) * 0.5;
     mid.z += 8;
     if(isLeft) { pose.lKnee=mid; pose.lFoot=footPos; }
     else { pose.rKnee=mid; pose.rFoot=footPos; }
  }

  static void _setActiveArm(StickmanSkeleton pose, {required bool isLeft, required double angle}) {
     v.Vector3 neck = pose.neck;
     double side = isLeft ? -6 : 6;

     // ASYMMETRICAL SWING:
     // Bias the sine wave to swing BACK more (-Z) and FRONT less (+Z).
     // Shift range: sin goes -1 to 1.
     // (sin - 0.3) goes -1.3 to 0.7.
     double swing = (sin(angle) - 0.3) * 0.9;

     double elbowBendOffset = max(0.0, swing) * 4.0;

     // Elbow Position
     v.Vector3 elbow = neck + v.Vector3(side, 10 - (elbowBendOffset*0.2), swing * 8);

     // Hand Position
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
