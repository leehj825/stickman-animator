import 'dart:math';
import 'package:vector_math/vector_math_64.dart' as v;
import 'stickman_skeleton.dart';
import 'stickman_animation.dart';

class StickmanGenerator {

  static void _applyStyle(StickmanSkeleton pose, StickmanSkeleton? style) {
    if (style != null) {
      pose.headRadius = style.headRadius;
      pose.strokeWidth = style.strokeWidth;
    }
  }

  static void _updateHead(StickmanSkeleton pose) {
     if(pose.head != null) {
       pose.setHead(pose.neck + v.Vector3(0, -7.3, 0));
     }
  }

  // --- 1. REFINED MARATHON RUN ---
  static StickmanClip generateRun(StickmanSkeleton? style) {
    List<StickmanKeyframe> frames = [];
    int totalFrames = 24;

    // Dynamic Lengths
    double legLen = 13.0;
    double armLen = 10.0;
    if (style != null) {
      legLen = style.hip.distanceTo(style.rKnee);
      armLen = style.neck.distanceTo(style.rElbow);
    }
    double strideScale = legLen / 13.0;

    for (int i = 0; i < totalFrames; i++) {
      double t = i / totalFrames;
      double angle = t * 2 * pi;

      StickmanSkeleton pose = StickmanSkeleton();
      _applyStyle(pose, style);

      pose.hip.y = cos(angle * 2) * 1.5;
      double hipTwist = sin(angle) * 0.15;
      _rotateY(pose.hip, hipTwist);

      pose.neck.setValues(0, -25 + pose.hip.y, 4);
      _rotateY(pose.neck, -hipTwist * 1.5);

      _setActiveArm(pose, isLeft: true, angle: angle + pi, length: armLen);
      _setActiveArm(pose, isLeft: false, angle: angle, length: armLen);

      _setSmoothLeg(pose, isLeft: true, angle: angle, length: legLen, strideScale: strideScale);
      _setSmoothLeg(pose, isLeft: false, angle: angle + pi, length: legLen, strideScale: strideScale);

      _updateHead(pose);
      frames.add(StickmanKeyframe(pose: pose, frameIndex: i));
    }
    return StickmanClip(name: "Run", keyframes: frames, fps: 30, isLooping: true);
  }

  // --- 2. ROUNDHOUSE KICK (Fixed Elbows) ---
  static StickmanClip generateKick(StickmanSkeleton? style) {
    List<StickmanKeyframe> frames = [];
    int totalFrames = 34;

    double thighLen = 13.0;
    double shinLen = 13.0;
    if (style != null) {
      thighLen = style.hip.distanceTo(style.rKnee);
      shinLen = style.rKnee.distanceTo(style.rFoot);
    }

    StickmanSkeleton stance = StickmanSkeleton();
    _applyStyle(stance, style);
    stance.lFoot.z = 5; stance.rFoot.z = -5;
    stance.lHand.setValues(-5, -15, 8); stance.rHand.setValues(5, -15, 5);

    for (int i = 0; i < totalFrames; i++) {
      double t = i / totalFrames;
      StickmanSkeleton pose = stance.clone();
      _applyStyle(pose, style);

      double leanAngle = 0.0;
      double hipSlide = 0.0;

      // Leg Logic
      if (t < 0.3) {
        double subT = t / 0.3;
        leanAngle = _lerp(0, -0.5, subT);
        hipSlide = _lerp(0, -5, subT);

        double thighPitch = _lerp(0, -pi/2 + 0.2, subT);
        double thighYaw = _lerp(0, pi/2, subT);
        pose.rKnee = pose.hip + _sphericalToCartesian(thighLen, thighPitch, thighYaw);

        double shinPitch = _lerp(0, pi * 0.8, subT);
        pose.rFoot = pose.rKnee + _sphericalToCartesian(shinLen, thighPitch + shinPitch, thighYaw);

      } else if (t < 0.5) {
        double subT = (t - 0.3) / 0.2;
        leanAngle = -0.6;
        hipSlide = -5;

        double thighYaw = _lerp(pi/2, pi * 0.7, subT);
        double thighPitch = -pi/2 - 0.4;
        pose.rKnee = pose.hip + _sphericalToCartesian(thighLen, thighPitch, thighYaw);

        double shinPitch = _lerp(pi * 0.8, 0.0, subT);
        pose.rFoot = pose.rKnee + _sphericalToCartesian(shinLen, thighPitch + shinPitch, thighYaw);

      } else if (t < 0.7) {
        double subT = (t - 0.5) / 0.2;
        leanAngle = -0.5;
        hipSlide = -5;

        double thighYaw = pi * 0.7;
        double thighPitch = _lerp(-pi/2 - 0.4, -pi/4, subT);
        pose.rKnee = pose.hip + _sphericalToCartesian(thighLen, thighPitch, thighYaw);

        double shinPitch = _lerp(0.0, pi * 0.9, subT);
        pose.rFoot = pose.rKnee + _sphericalToCartesian(shinLen, thighPitch + shinPitch, thighYaw);

      } else {
        double subT = (t - 0.7) / 0.3;
        leanAngle = _lerp(-0.5, 0, subT);
        hipSlide = _lerp(-5, 0, subT);

        v.Vector3 landingKnee = pose.hip + v.Vector3(3, thighLen*0.9, 0);
        v.Vector3 landingFoot = landingKnee + v.Vector3(3, shinLen*0.9, 0);
        v.Vector3 recoilKnee = pose.hip + _sphericalToCartesian(thighLen, -pi/4, pi * 0.7);
        pose.rKnee = _lerpVector(recoilKnee, landingKnee, subT);
        pose.rFoot = _lerpVector(pose.rKnee + v.Vector3(0,shinLen*0.8,0), landingFoot, subT);
      }

      // Apply Body Lean
      pose.hip.x = hipSlide;
      pose.neck.setValues(0, -25, 0);
      _rotateX(pose.neck, leanAngle);
      pose.neck.add(pose.hip);

      // --- FIX: ARMS & ELBOWS ROTATE WITH BODY ---

      // Left Arm (Guard Face)
      v.Vector3 lArmOffset = v.Vector3(-8, 5, 10);
      _rotateX(lArmOffset, leanAngle);
      pose.lHand = pose.neck + lArmOffset;

      v.Vector3 lElbowOffset = v.Vector3(-6, 8, 2); // Elbow tucked
      _rotateX(lElbowOffset, leanAngle);
      pose.lElbow = pose.neck + lElbowOffset;

      // Right Arm (Balance)
      v.Vector3 rArmOffset = v.Vector3(8, 5, 2);
      _rotateX(rArmOffset, leanAngle);
      pose.rHand = pose.neck + rArmOffset;

      v.Vector3 rElbowOffset = v.Vector3(6, 8, 0); // Elbow out
      _rotateX(rElbowOffset, leanAngle);
      pose.rElbow = pose.neck + rElbowOffset;

      _updateHead(pose);
      frames.add(StickmanKeyframe(pose: pose, frameIndex: i));
    }
    return StickmanClip(name: "Kick", keyframes: frames, fps: 30, isLooping: false);
  }

  // --- 3. SQUAT JUMP ---
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
        double subT = t / 0.3;
        double squash = sin(subT * pi) * 12;
        pose.hip.y += squash;
        double lean = squash * 0.5;
        pose.neck.setValues(0, pose.hip.y - 25 + (squash * 0.5), lean);

        double armPull = sin(subT * pi) * 10;
        pose.lElbow = pose.neck + v.Vector3(-6, 7.5, -armPull);
        pose.rElbow = pose.neck + v.Vector3(6, 7.5, -armPull);
        pose.lHand.setValues(-8, pose.neck.y + 10, -5); pose.rHand.setValues(8, pose.neck.y + 10, -5);

        double kneeY = (pose.hip.y + 24) * 0.5;
        pose.lKnee = v.Vector3(-4.1 - (3 * subT), kneeY, 0);
        pose.rKnee = v.Vector3(5.0 + (3 * subT), kneeY, 0);

      } else if (t < 0.5) {
        pose.hip.y -= jumpY;
        pose.neck.setValues(0, pose.hip.y - 25, 0);
        pose.lElbow = pose.neck + v.Vector3(-6, 7.5, 5); pose.rElbow = pose.neck + v.Vector3(6, 7.5, 5);
        pose.lHand.setValues(-8, pose.neck.y + 25, 10); pose.rHand.setValues(8, pose.neck.y + 25, 10);
        pose.lKnee.y = pose.hip.y + 20; pose.lFoot.y = pose.hip.y + 35;
        pose.rKnee.y = pose.hip.y + 20; pose.rFoot.y = pose.hip.y + 35;

      } else if (t < 0.8) {
        double subT = (t - 0.5) / 0.3;
        pose.hip.y -= jumpY;
        pose.neck.setValues(0, pose.hip.y - 25, 0);
        double elbowZ = _lerp(5, 0, subT);
        pose.lElbow = pose.neck + v.Vector3(-6, 7.5, elbowZ); pose.rElbow = pose.neck + v.Vector3(6, 7.5, elbowZ);
        double handYOffset = _lerp(25, 20, subT);
        pose.lHand.y = pose.neck.y + handYOffset; pose.rHand.y = pose.neck.y + handYOffset;
        pose.lHand.x = -8; pose.rHand.x = 8;
        pose.lKnee.y = pose.hip.y + 15; pose.lFoot.y = pose.hip.y + 30;
        pose.rKnee.y = pose.hip.y + 15; pose.rFoot.y = pose.hip.y + 30;

      } else {
        double subT = (t - 0.8) / 0.2;
        double absorb = sin(subT * pi) * 8;
        pose.hip.y += absorb;
        pose.neck.setValues(0, pose.hip.y - 25 + (absorb*0.5), absorb * 0.5);
        pose.lHand.setValues(-8, pose.neck.y + 20, 0); pose.rHand.setValues(8, pose.neck.y + 20, 0);
        pose.lElbow = pose.neck + v.Vector3(-6, 7.5, 0); pose.rElbow = pose.neck + v.Vector3(6, 7.5, 0);
        double kneeY = (pose.hip.y + 24) * 0.5;
        pose.lKnee.y = kneeY; pose.rKnee.y = kneeY;
        pose.lFoot.y = 24; pose.rFoot.y = 24;
      }
      _updateHead(pose);
      frames.add(StickmanKeyframe(pose: pose, frameIndex: i));
    }
    return StickmanClip(name: "Jump", keyframes: frames, fps: 30, isLooping: false);
  }

  static StickmanClip generateEmpty(StickmanSkeleton? style) {
    List<StickmanKeyframe> frames = [];
    for(int i=0; i<30; i++) {
        StickmanSkeleton p = style != null ? style.clone() : StickmanSkeleton();
        frames.add(StickmanKeyframe(pose: p, frameIndex: i));
    }
    return StickmanClip(name: "Custom", keyframes: frames, fps: 30, isLooping: true);
  }

  // --- HELPERS ---

  static v.Vector3 _sphericalToCartesian(double r, double pitch, double yaw) {
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

  static void _rotateX(v.Vector3 vec, double angle) {
    double cosA = cos(angle);
    double sinA = sin(angle);
    double y = vec.y;
    double z = vec.z;
    vec.y = y * cosA - z * sinA;
    vec.z = y * sinA + z * cosA;
  }

  static void _setSmoothLeg(StickmanSkeleton pose, {required bool isLeft, required double angle, required double length, required double strideScale}) {
     double side = isLeft ? -3 : 3;
     double stride = sin(angle) * (13.0 * strideScale);
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
     mid.z += length * 0.6;
     if(isLeft) { pose.lKnee=mid; pose.lFoot=footPos; }
     else { pose.rKnee=mid; pose.rFoot=footPos; }
  }

  static void _setActiveArm(StickmanSkeleton pose, {required bool isLeft, required double angle, required double length}) {
     v.Vector3 neck = pose.neck;
     double side = isLeft ? -6 : 6;
     double swing = (sin(angle) - 0.3) * 0.9;
     double elbowBendOffset = max(0.0, swing) * 4.0;

     v.Vector3 elbow = neck + v.Vector3(side, length, swing * 8);
     v.Vector3 hand = elbow + v.Vector3(0, length, 5 + swing * 5 + elbowBendOffset);

     if(isLeft) { pose.lElbow=elbow; pose.lHand=hand; }
     else { pose.rElbow=elbow; pose.rHand=hand; }
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
  static v.Vector3 _lerpVector(v.Vector3 a, v.Vector3 b, double t) => v.Vector3(_lerp(a.x,b.x,t), _lerp(a.y,b.y,t), _lerp(a.z,b.z,t));
}
