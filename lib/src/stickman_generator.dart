import 'dart:math';
import 'package:vector_math/vector_math_64.dart' as v;
import 'stickman_skeleton.dart';
import 'stickman_animation.dart';

/// Generates procedural animation clips with high-fidelity biomechanical math
class StickmanGenerator {

  // --- Helper Functions ---

  /// Rotates a point around the X-axis
  static v.Vector3 _rotateX(v.Vector3 point, double angle) {
    final rot = v.Matrix3.rotationX(angle);
    return rot.transform(point);
  }

  /// Rotates a point around the Y-axis
  static v.Vector3 _rotateY(v.Vector3 point, double angle) {
    final rot = v.Matrix3.rotationY(angle);
    return rot.transform(point);
  }

  /// Rotates a point around the Z-axis
  static v.Vector3 _rotateZ(v.Vector3 point, double angle) {
    final rot = v.Matrix3.rotationZ(angle);
    return rot.transform(point);
  }

  /// Linear interpolation between two vectors
  static v.Vector3 _lerpVector(v.Vector3 a, v.Vector3 b, double t) {
    return v.Vector3(
      a.x + (b.x - a.x) * t,
      a.y + (b.y - a.y) * t,
      a.z + (b.z - a.z) * t,
    );
  }

  /// Helper for "Run": Returns a foot position based on a cycloid path
  /// [phase] is 0.0 to 1.0 (cycle progress)
  static v.Vector3 _cycloidFoot(double phase) {
    // Ground Phase: 0.0 to 0.5 (Foot moves backward linearly to push body forward)
    // Air Phase: 0.5 to 1.0 (Foot moves forward in a high arc)

    // Normalized time for each phase
    if (phase < 0.5) {
      // Ground Contact (Stance)
      double t = phase / 0.5; // 0 to 1
      // Foot moves from Front (+Z) to Back (-Z) relative to hip, sticking to ground (constant Y)
      double strideLength = 20.0;
      double z = strideLength * (0.5 - t); // +10 to -10
      return v.Vector3(0, 24.5, z); // 24.5 is roughly leg length fully extended
    } else {
      // Swing Phase
      double t = (phase - 0.5) / 0.5; // 0 to 1
      // Foot moves from Back (-Z) to Front (+Z) with height
      double strideLength = 20.0;
      double z = -strideLength * 0.5 + (strideLength * t); // -10 to +10

      // Height Arc (Parabola or Sine)
      // High knee lift for running
      double lift = sin(t * pi) * 12.0;

      return v.Vector3(0, 24.5 - lift, z); // Note: In this system Y is down?
      // Checking skeleton: Hip is (1,0,0), Knee (-4, 11, 0), Foot (-7, 24, 0).
      // Yes, Y increases downwards. So 0 is hip, positive is feet.
      // To lift foot, Y should decrease.
    }
  }

  // --- Animation Generators ---

  /// Generates a "Realistic Run" (Rotary Gallop logic)
  static StickmanClip generateRun() {
    final List<StickmanKeyframe> frames = [];
    const int totalFrames = 30; // 30 frames loop

    for (int i = 0; i < totalFrames; i++) {
      double t = i / totalFrames; // 0.0 to 1.0
      final pose = StickmanSkeleton();

      // --- Hips (The Engine) ---
      // Bob: Up/Down twice per cycle (lowest when foot planted, i.e., at t=0.25 and t=0.75)
      // Cycle: L_Plant(0.0-0.5), R_Plant(0.5-1.0)
      // Center of support is roughly at 0.25 (left) and 0.75 (right) -> Lowest Y (highest value)
      // Actually, highest point (lowest Y value) is during flight (transition).
      // Let's model a simple bob: sin(2*t)
      double bob = sin(t * 4 * pi) * 1.5; // 2 cycles
      pose.hip.y += bob;

      // Lean: Permanent forward pitch
      // We apply this by rotating the whole body or just moving neck/head forward
      // Let's rotate the spine slightly. Neck is usually (0, -14.7, 0).
      // Rotate neck forward (around X axis).
      pose.neck = _rotateX(v.Vector3(0, -14.7, 0), 0.2) + pose.hip;
      // Correct neck position based on hip

      // Head follows neck
      if (pose.head != null) {
         pose.setHead(pose.neck + _rotateX(v.Vector3(0, -8, 0), 0.2));
      }

      // Twist: Rotate hips on Y axis to favor advancing leg
      // Left leg forward at t=0.75 (end of swing), Right at t=0.25
      double twistAngle = sin(t * 2 * pi) * 0.15;

      // --- Feet (The Wheel) ---
      // Left Leg Phase: Starts at 0.0 (impact) -> 0.5 (toe off) -> 1.0 (impact)
      // Right Leg Phase: Offset by 0.5

      // Adjust phases so t=0 matches a pose (e.g., Left Contact)
      double lPhase = (t + 0.0) % 1.0;
      double rPhase = (t + 0.5) % 1.0;

      // Calculate Foot Targets in Hip Space
      v.Vector3 lTarget = _cycloidFoot(lPhase);
      v.Vector3 rTarget = _cycloidFoot(rPhase);

      // Apply Twist to Hip/Leg attachments
      // We simulate twist by rotating the leg attachment points or the targets
      lTarget = _rotateY(lTarget, twistAngle);
      rTarget = _rotateY(rTarget, twistAngle);

      // Inverse Kinematics (Simple 2-Bone IK) would be ideal, but here we set Knee/Foot directly.
      // Since we don't have a full IK solver exposed in this scope easily, we approximate.
      // But the skeleton allows setting Knee and Foot positions directly.
      // We just need to ensure the Knee is placed logically between Hip and Foot.

      // Left Leg Placement
      pose.lFoot = pose.hip + lTarget;
      // Knee estimation: Midpoint + offset for bend
      v.Vector3 lMid = (pose.hip + pose.lFoot) * 0.5;
      // Knee bends forward (positive Z? No, knees bend forward, so Z decreases?)
      // Check skeleton: Knee is (..., 11.8, 0). Foot is (..., 24.5, 0).
      // Standard T-pose: Legs straight down.
      // Bending knee: Knee moves forward (Z increases or decreases? Z is depth.)
      // Let's assume +Z is forward for the character based on arm swing logic in previous code.
      // Actually, standard classic stickman usually is 2D planar on X/Y, but we are 3D.
      // Previous code: lKnee = _rotateX(..., legSwing).
      // If legSwing is positive, it rotates X.
      // Let's use simple trigonometry for knee hint.
      // Push knee forward (+Z) based on how close foot is to hip.
      double lDist = lTarget.length;
      double lKneeProtrusion = sqrt(max(0, 144 - (lDist/2)*(lDist/2))); // 12 unit thigh length approx
      // Direction perpendicular to leg line.
      pose.lKnee = lMid + v.Vector3(0, 0, lKneeProtrusion); // Simple forward bend

      // Right Leg Placement
      pose.rFoot = pose.hip + rTarget;
      double rDist = rTarget.length;
      double rKneeProtrusion = sqrt(max(0, 144 - (rDist/2)*(rDist/2)));
      pose.rKnee = (pose.hip + pose.rFoot) * 0.5 + v.Vector3(0, 0, rKneeProtrusion);


      // --- Arms ---
      // Swing opposite to legs.
      // Left leg (lPhase) determines Left Arm (opposite phase usually, so matches Right Leg phase)
      // Arm Phase = lPhase + 0.5 = rPhase

      double armSwing = sin(t * 2 * pi) * 0.8;

      // Left Arm (Matches Right Leg) -> Swing Forward when Right Leg is Forward
      // Right Leg is forward during its swing (0.5-1.0 of rPhase).
      // t=0.75 -> Right Leg Forward. armSwing is -1. Left Arm should be forward.
      // Wait, contralateral: Left Arm forward when Right Leg forward.

      // Left Arm
      double lArmAngle = -armSwing;
      // Bend elbow more on forward swing (when angle is negative/forward)
      double lElbowBend = (lArmAngle < 0) ? 1.5 : 0.2;

      pose.lElbow = pose.neck + _rotateX(v.Vector3(-6, 10, 0), lArmAngle);
      pose.lHand = pose.lElbow + _rotateX(v.Vector3(0, 10, 0), lArmAngle - lElbowBend);

      // Right Arm
      double rArmAngle = armSwing;
      double rElbowBend = (rArmAngle < 0) ? 1.5 : 0.2;

      pose.rElbow = pose.neck + _rotateX(v.Vector3(6, 10, 0), rArmAngle);
      pose.rHand = pose.rElbow + _rotateX(v.Vector3(0, 10, 0), rArmAngle - rElbowBend);

      frames.add(StickmanKeyframe(pose: pose, frameIndex: i));
    }

    return StickmanClip(name: "Run", keyframes: frames);
  }

  /// Generates a "Power Kick" (4-Stage Martial Arts Front Kick)
  static StickmanClip generateKick() {
    final List<StickmanKeyframe> frames = [];
    const int totalFrames = 40; // More frames for detail

    final v.Vector3 stanceHip = v.Vector3(1, 0, 0);
    final v.Vector3 stanceNeck = v.Vector3(0, -14.7, 0);

    for (int i = 0; i < totalFrames; i++) {
      double t = i / (totalFrames - 1);
      final pose = StickmanSkeleton();

      // State Machine
      // 0.0 - 0.3: Chamber (Lift knee, lean back)
      // 0.3 - 0.45: Extension (Snap kick)
      // 0.45 - 0.6: Recoil (Retract)
      // 0.6 - 1.0: Return (Land)

      // Base Pose (Left leg planted)
      pose.lFoot = stanceHip + v.Vector3(-4, 24.5, 0); // Planted slightly wide
      pose.lKnee = stanceHip + v.Vector3(-3, 12, 2); // Slight bend

      // Torso Lean (increases during kick)
      double lean = 0.0;
      if (t < 0.3) lean = (t / 0.3) * 0.3; // Lean back to 0.3 rad
      else if (t < 0.6) lean = 0.3;
      else lean = 0.3 * (1 - (t - 0.6) / 0.4);

      pose.neck = stanceHip + _rotateX(stanceNeck, -lean); // Lean back (-X rotation)
      if (pose.head != null) pose.setHead(pose.neck + _rotateX(v.Vector3(0, -8, 0), -lean));

      // Right Leg (The Kicker)
      v.Vector3 rHipPos = stanceHip;
      v.Vector3 rKneePos;
      v.Vector3 rFootPos;

      if (t < 0.3) {
        // --- Stage 1: Chamber ---
        double st = t / 0.3; // 0 to 1
        // Lift Knee High, Foot close to hip
        v.Vector3 startKnee = stanceHip + v.Vector3(3, 12, 0);
        v.Vector3 targetKnee = stanceHip + v.Vector3(2, 0, 8); // High up, forward
        rKneePos = _lerpVector(startKnee, targetKnee, sin(st * pi / 2)); // Ease out

        v.Vector3 startFoot = stanceHip + v.Vector3(3, 24.5, 0);
        v.Vector3 targetFoot = stanceHip + v.Vector3(2, 12, 0); // Tucked under
        rFootPos = _lerpVector(startFoot, targetFoot, st);

      } else if (t < 0.45) {
        // --- Stage 2: Extension ---
        double st = (t - 0.3) / 0.15; // 0 to 1
        // Knee locks in place (or moves slightly up), Foot snaps out
        v.Vector3 chamberKnee = stanceHip + v.Vector3(2, 0, 8);
        rKneePos = chamberKnee;

        v.Vector3 chamberFoot = stanceHip + v.Vector3(2, 12, 0);
        v.Vector3 extendFoot = chamberKnee + v.Vector3(0, -5, 12); // Way out forward/up
        // Snap!
        rFootPos = _lerpVector(chamberFoot, extendFoot, pow(st, 0.5).toDouble()); // Fast snap

      } else if (t < 0.6) {
        // --- Stage 3: Recoil ---
        double st = (t - 0.45) / 0.15;
        // Pull foot back
        v.Vector3 chamberKnee = stanceHip + v.Vector3(2, 0, 8);
        rKneePos = chamberKnee;

        v.Vector3 extendFoot = chamberKnee + v.Vector3(0, -5, 12);
        v.Vector3 recoilFoot = stanceHip + v.Vector3(2, 12, 0);
        rFootPos = _lerpVector(extendFoot, recoilFoot, st);

      } else {
        // --- Stage 4: Return ---
        double st = (t - 0.6) / 0.4;
        // Lower leg
        v.Vector3 chamberKnee = stanceHip + v.Vector3(2, 0, 8);
        v.Vector3 endKnee = stanceHip + v.Vector3(3, 12, 0);
        rKneePos = _lerpVector(chamberKnee, endKnee, st);

        v.Vector3 recoilFoot = stanceHip + v.Vector3(2, 12, 0);
        v.Vector3 endFoot = stanceHip + v.Vector3(3, 24.5, 0);
        rFootPos = _lerpVector(recoilFoot, endFoot, st);
      }

      pose.rKnee = rKneePos;
      pose.rFoot = rFootPos;

      // Arms (Guard)
      // Hands up near face
      pose.lElbow = pose.neck + v.Vector3(-4, 6, 4);
      pose.lHand = pose.lElbow + v.Vector3(0, -6, 4); // Fist near chin

      pose.rElbow = pose.neck + v.Vector3(4, 6, 2);
      pose.rHand = pose.rElbow + v.Vector3(0, -6, 2); // Lower guard

      frames.add(StickmanKeyframe(pose: pose, frameIndex: i));
    }

    return StickmanClip(name: "Kick", keyframes: frames);
  }

  /// Generates an "Athletic Jump" (Squat-to-Tuck)
  static StickmanClip generateJump() {
    final List<StickmanKeyframe> frames = [];
    const int totalFrames = 35;

    for (int i = 0; i < totalFrames; i++) {
      double t = i / (totalFrames - 1);
      final pose = StickmanSkeleton();

      // Phases:
      // 0.0 - 0.2: Anticipation (Squat)
      // 0.2 - 0.3: Propulsion (Launch)
      // 0.3 - 0.7: Apex (Tuck)
      // 0.7 - 0.85: Extension (Prepare to land)
      // 0.85 - 1.0: Landing (Squat absorb)

      double hipHeight = 0.0;
      double squatFactor = 0.0; // 0 = stand, 1 = deep squat
      double tuckFactor = 0.0; // 0 = straight, 1 = knees to chest

      if (t < 0.2) {
        // Anticipation
        double st = t / 0.2;
        squatFactor = sin(st * pi); // Dip down and slightly up? No, dip down.
        // Actually sin(st * pi/2) -> 0 to 1
        squatFactor = sin(st * pi / 2) * 0.8;
      } else if (t < 0.3) {
        // Launch
        double st = (t - 0.2) / 0.1;
        squatFactor = 0.8 * (1 - st); // Un-squat rapidly
        hipHeight = st * 10.0; // Start rising
      } else if (t < 0.7) {
        // Air / Apex
        double st = (t - 0.3) / 0.4;
        // Parabolic Height
        // 0 to 1 -> 0 to 1 to 0
        // We started at height 10. Go up to 30.
        hipHeight = 10.0 + 20.0 * sin(st * pi);

        // Tuck
        tuckFactor = sin(st * pi); // Tuck in middle of air
      } else if (t < 0.85) {
        // Extension
        double st = (t - 0.7) / 0.15;
        hipHeight = 10.0 * (1 - st); // Fall back to ground
        tuckFactor = 0.0;
        squatFactor = 0.0; // Legs straight to catch
      } else {
        // Landing
        double st = (t - 0.85) / 0.15;
        squatFactor = sin(st * pi) * 0.8; // Deep absorb
      }

      // Apply Hip Height
      pose.hip.y -= hipHeight;
      pose.neck.y -= hipHeight;
      if (pose.head != null) pose.setHead(pose.neck + v.Vector3(0, -8, 0));

      // Calculate Legs based on Squat/Tuck
      // Standard Leg: Hip(0) -> Knee(12) -> Foot(24)

      if (hipHeight > 5.0) {
        // AIRBORNE
        // Tuck logic: Knees come UP (-Y relative to hip)
        double tuckOffset = tuckFactor * 10.0;

        pose.lKnee = pose.hip + v.Vector3(-3, 12 - tuckOffset, 5 * tuckFactor);
        pose.lFoot = pose.lKnee + v.Vector3(0, 12, -5 * tuckFactor); // Toes point down/back

        pose.rKnee = pose.hip + v.Vector3(3, 12 - tuckOffset, 5 * tuckFactor);
        pose.rFoot = pose.rKnee + v.Vector3(0, 12, -5 * tuckFactor);
      } else {
        // GROUNDED (Squatting)
        // Feet are fixed on ground
        v.Vector3 lFootPos = v.Vector3(-4, 24.5, 0); // World space ground
        v.Vector3 rFootPos = v.Vector3(4, 24.5, 0);

        pose.lFoot = lFootPos;
        pose.rFoot = rFootPos;

        // Knee IK logic
        // Hip is at pose.hip. Foot is at lFootPos.
        // Find knee.
        v.Vector3 hipToFootL = lFootPos - pose.hip;
        double distL = hipToFootL.length;
        // Simple heuristic: Knee moves outward/forward when squatting
        v.Vector3 midL = (pose.hip + lFootPos) * 0.5;
        double kneeOut = sqrt(max(0, 144 - (distL/2)*(distL/2)));
        pose.lKnee = midL + v.Vector3(-kneeOut * 0.5, 0, kneeOut * 0.8); // Out and Forward

        v.Vector3 hipToFootR = rFootPos - pose.hip;
        v.Vector3 midR = (pose.hip + rFootPos) * 0.5;
        pose.rKnee = midR + v.Vector3(kneeOut * 0.5, 0, kneeOut * 0.8);
      }

      // Arms
      // Anticipation: Back
      // Launch: Swing Up
      // Tuck: Hold?
      // Landing: Balance

      double armAngle = 0.0;
      if (t < 0.2) armAngle = 1.0; // Back
      else if (t < 0.3) armAngle = -2.5; // Up!
      else if (t < 0.7) armAngle = -2.0; // Hold Up
      else armAngle = 0.5; // Balance

      // Lerp arm angle smoothly? We are stepping discreetly, but function is continuous enough.

      pose.lElbow = pose.neck + _rotateX(v.Vector3(-6, 10, 0), armAngle);
      pose.lHand = pose.lElbow + _rotateX(v.Vector3(0, 10, 0), armAngle - 0.2);

      pose.rElbow = pose.neck + _rotateX(v.Vector3(6, 10, 0), armAngle);
      pose.rHand = pose.rElbow + _rotateX(v.Vector3(0, 10, 0), armAngle - 0.2);

      frames.add(StickmanKeyframe(pose: pose, frameIndex: i));
    }

    return StickmanClip(name: "Jump", keyframes: frames);
  }

  /// Generates an empty clip
  static StickmanClip generateEmpty() {
    return StickmanClip.empty(30);
  }
}
