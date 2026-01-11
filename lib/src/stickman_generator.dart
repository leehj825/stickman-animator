import 'dart:math';
import 'package:vector_math/vector_math_64.dart' as v;
import 'stickman_skeleton.dart';
import 'stickman_animation.dart';

/// Generates procedural animation clips
class AnimationFactory {

  /// Helper to rotate local points
  static v.Vector3 _rotateX(v.Vector3 point, double angle) {
    final rot = v.Matrix3.rotationX(angle);
    return rot.transform(point);
  }

  /// Generates a "Run" clip
  static StickmanClip generateRun() {
    final List<StickmanKeyframe> frames = [];
    const int totalFrames = 30;

    for (int i = 0; i < totalFrames; i++) {
      double t = (i / totalFrames) * 2 * pi; // 0 to 2pi
      final pose = StickmanSkeleton();

      // Sine wave parameters
      double legSwing = sin(t) * 0.8;
      double armSwing = cos(t) * 0.8;
      double bounce = sin(t * 2).abs() * 2.0; // Bounce twice per cycle

      // Apply bounce to spine
      pose.neck.y -= bounce;
      if (pose.head != null) {
         pose.setHead(pose.neck + v.Vector3(0, -8, 0));
      }

      // Legs (Standard Stickman Topology: Knee relative to Hip)
      // Left Leg
      pose.lKnee = _rotateX(v.Vector3(-3, 12, 0), legSwing) + pose.hip;
      pose.lFoot = _rotateX(v.Vector3(-3, 12, 0), legSwing + 0.2) + pose.lKnee;

      // Right Leg
      pose.rKnee = _rotateX(v.Vector3(3, 12, 0), -legSwing) + pose.hip;
      pose.rFoot = _rotateX(v.Vector3(3, 12, 0), -legSwing + 0.2) + pose.rKnee;

      // Arms (Standard Stickman Topology: Elbow relative to Neck)
      // Left Arm
      double lArmAngle = -armSwing;
      pose.lElbow = _rotateX(v.Vector3(-6, 10, 0), lArmAngle) + pose.neck;
      pose.lHand = _rotateX(v.Vector3(0, 10, 0), lArmAngle - 0.3) + pose.lElbow;

      // Right Arm
      double rArmAngle = armSwing;
      pose.rElbow = _rotateX(v.Vector3(6, 10, 0), rArmAngle) + pose.neck;
      pose.rHand = _rotateX(v.Vector3(0, 10, 0), rArmAngle - 0.3) + pose.rElbow;

      frames.add(StickmanKeyframe(pose: pose, frameIndex: i));
    }

    return StickmanClip(name: "Run", keyframes: frames);
  }

  /// Generates a "Jump" clip
  static StickmanClip generateJump() {
    final List<StickmanKeyframe> frames = [];
    const int totalFrames = 30;

    for (int i = 0; i < totalFrames; i++) {
      double progress = i / (totalFrames - 1); // 0.0 to 1.0
      final pose = StickmanSkeleton();

      // Parabolic jump arc for height (up and down)
      // 4 * x * (1-x) gives a parabola from 0 to 1 to 0.
      double height = 20.0 * 4 * progress * (1.0 - progress);

      // Move Root (Hip) up
      pose.hip.y -= height;
      pose.neck.y -= height;
      if (pose.head != null) {
         pose.setHead(pose.neck + v.Vector3(0, -8, 0));
      }

      // Crouch anticipation at start, Extension in middle, Crouch landing at end
      double legBend = 0.0;
      if (progress < 0.2) {
         // Crouch (Anticipation)
         legBend = sin(progress * 5 * pi) * 0.5; // Quick crouch
      } else if (progress > 0.8) {
         // Crouch (Landing)
         legBend = sin((progress - 0.8) * 5 * pi) * 0.5;
      }

      // Arms swing up
      double armAngle = -2.5 * sin(progress * pi); // Arms go up

      // Legs
      pose.lKnee = _rotateX(v.Vector3(-3, 12, 0), legBend) + pose.hip;
      pose.lFoot = _rotateX(v.Vector3(-3, 12, 0), legBend * 2) + pose.lKnee;

      pose.rKnee = _rotateX(v.Vector3(3, 12, 0), legBend) + pose.hip;
      pose.rFoot = _rotateX(v.Vector3(3, 12, 0), legBend * 2) + pose.rKnee;

      // Arms
      pose.lElbow = _rotateX(v.Vector3(-6, 10, 0), armAngle) + pose.neck;
      pose.lHand = _rotateX(v.Vector3(0, 10, 0), armAngle - 0.5) + pose.lElbow;

      pose.rElbow = _rotateX(v.Vector3(6, 10, 0), armAngle) + pose.neck;
      pose.rHand = _rotateX(v.Vector3(0, 10, 0), armAngle - 0.5) + pose.rElbow;

      frames.add(StickmanKeyframe(pose: pose, frameIndex: i));
    }

    return StickmanClip(name: "Jump", keyframes: frames);
  }

  /// Generates a "Kick" clip
  static StickmanClip generateKick() {
    final List<StickmanKeyframe> frames = [];
    const int totalFrames = 30;

    for (int i = 0; i < totalFrames; i++) {
      double t = i / totalFrames;
      final pose = StickmanSkeleton();

      // Right leg kicks forward
      double kickAngle = 0.0;
      if (t < 0.5) {
         // Wind up
         kickAngle = -sin(t * 2 * pi) * 0.5;
      } else {
         // Kick!
         kickAngle = sin((t - 0.5) * 2 * pi) * 1.5;
      }

      // Left leg plants (stays roughly same)
      pose.lKnee = v.Vector3(-3, 12, 0) + pose.hip;
      pose.lFoot = v.Vector3(-3, 24, 0) + pose.lKnee; // Straight

      // Right leg action
      pose.rKnee = _rotateX(v.Vector3(3, 12, 0), -kickAngle) + pose.hip;
      pose.rFoot = _rotateX(v.Vector3(3, 12, 0), -kickAngle * 0.5) + pose.rKnee; // Slight knee bend

      // Arms for balance
      pose.lElbow = _rotateX(v.Vector3(-6, 10, 0), 0.5) + pose.neck;
      pose.lHand = _rotateX(v.Vector3(0, 10, 0), 0.5) + pose.lElbow;

      pose.rElbow = _rotateX(v.Vector3(6, 10, 0), -0.5) + pose.neck;
      pose.rHand = _rotateX(v.Vector3(0, 10, 0), -0.5) + pose.rElbow;

      frames.add(StickmanKeyframe(pose: pose, frameIndex: i));
    }

    return StickmanClip(name: "Kick", keyframes: frames);
  }

  /// Generates an empty (default pose) clip for custom animation
  static StickmanClip generateEmpty() {
    return StickmanClip.empty(30);
  }
}
