import 'dart:math';
import 'package:vector_math/vector_math_64.dart' as v;
import 'stickman_skeleton.dart';
import 'stickman_animation.dart';

class StickmanGenerator {

  // --- HELPER: Interpolate between two skeletons ---
  static StickmanSkeleton _lerpPose(StickmanSkeleton a, StickmanSkeleton b, double t) {
    StickmanSkeleton result = a.clone();
    result.lerp(b, t);
    return result;
  }

  // --- HELPER: Generate Frames from Key Poses ---
  // keyPoses is a Map where key = normalized time (0.0 to 1.0) and value = Pose
  static List<StickmanKeyframe> _generateFramesFromPoses(
      Map<double, StickmanSkeleton> keyPoses, int totalFrames, StickmanSkeleton? style) {

    List<StickmanKeyframe> frames = [];
    List<double> times = keyPoses.keys.toList()..sort();

    for (int i = 0; i < totalFrames; i++) {
      double t = i / (totalFrames - 1); // 0.0 to 1.0 inclusive (or close for looping)

      // For looping animations, we might want i / totalFrames and handle wrap around,
      // but here we assume the user provides 0.0 and 1.0 poses match if looping.

      // Find surrounding keyframes
      double t1 = 0.0;
      double t2 = 1.0;
      StickmanSkeleton p1 = keyPoses[times.first]!;
      StickmanSkeleton p2 = keyPoses[times.last]!;

      for (int k = 0; k < times.length - 1; k++) {
        if (t >= times[k] && t <= times[k+1]) {
          t1 = times[k];
          t2 = times[k+1];
          p1 = keyPoses[t1]!;
          p2 = keyPoses[t2]!;
          break;
        }
      }

      // Local interpolation factor
      double localT = (t - t1) / (t2 - t1);
      if ((t2 - t1) == 0) localT = 0;

      StickmanSkeleton pose = _lerpPose(p1, p2, localT);

      // Apply global style if provided
      if (style != null) {
        pose.headRadius = style.headRadius;
        pose.strokeWidth = style.strokeWidth;
      }

      frames.add(StickmanKeyframe(pose: pose, frameIndex: i));
    }
    return frames;
  }

  // --- HELPER: Pose Construction ---
  // Creates a skeleton with specific limb positions
  static StickmanSkeleton _createPose({
    v.Vector3? hip,
    v.Vector3? neck,
    v.Vector3? lHand, v.Vector3? rHand,
    v.Vector3? lElbow, v.Vector3? rElbow,
    v.Vector3? lFoot, v.Vector3? rFoot,
    v.Vector3? lKnee, v.Vector3? rKnee,
  }) {
    final s = StickmanSkeleton();
    if (hip != null) s.hip.setFrom(hip);
    if (neck != null) s.neck.setFrom(neck);
    else s.neck.setFrom(s.hip + v.Vector3(0, -15, 0));

    // Default head relative to neck
    s.setHead(s.neck + v.Vector3(0, -8, 0));

    if (lHand != null) s.lHand.setFrom(lHand);
    if (rHand != null) s.rHand.setFrom(rHand);
    if (lElbow != null) s.lElbow.setFrom(lElbow);
    if (rElbow != null) s.rElbow.setFrom(rElbow);

    if (lFoot != null) s.lFoot.setFrom(lFoot);
    if (rFoot != null) s.rFoot.setFrom(rFoot);
    if (lKnee != null) s.lKnee.setFrom(lKnee);
    if (rKnee != null) s.rKnee.setFrom(rKnee);

    return s;
  }

  // --- 1. RUN ANIMATION (Looping) ---
  static StickmanClip generateRun(StickmanSkeleton? style) {
    // We define 5 key poses for a full cycle (0% -> 25% -> 50% -> 75% -> 100%)
    // 0% and 100% must be identical for looping.
    // Z-Axis: +Z is Forward, -Z is Backward.
    // Y-Axis: +Y is Down. Ground is approx 25.

    final poses = <double, StickmanSkeleton>{};

    // POSE 1: Left Heel Strike (Left Leg Forward, Right Arm Forward)
    poses[0.0] = _createPose(
      hip: v.Vector3(0, 2, 0),
      neck: v.Vector3(0, -13, 5), // Lean forward
      // Left Leg (Front)
      lKnee: v.Vector3(-3, 15, 10), // Knee Forward
      lFoot: v.Vector3(-3, 25, 12), // Foot Forward on ground
      // Right Leg (Back - Toe Off)
      rKnee: v.Vector3(3, 15, -5),
      rFoot: v.Vector3(3, 20, -15), // Foot Back in air
      // Left Arm (Back - Counter balance)
      lElbow: v.Vector3(-6, -5, -8), // Elbow Back
      lHand: v.Vector3(-8, 5, -12),
      // Right Arm (Front)
      rElbow: v.Vector3(6, -5, 5),
      rHand: v.Vector3(8, -8, 12), // Hand Forward/Up
    );

    // POSE 2: Mid-Stance Left (Right Leg Passing)
    poses[0.25] = _createPose(
      hip: v.Vector3(0, 0, 0), // Lowest point
      neck: v.Vector3(0, -15, 5),
      // Left Leg (Supporting)
      lKnee: v.Vector3(-3, 12, 5), // Slight bend
      lFoot: v.Vector3(-3, 25, 0), // Directly under hip
      // Right Leg (Passing)
      rKnee: v.Vector3(3, 10, 15), // High knee forward
      rFoot: v.Vector3(3, 20, 5),
      // Arms Mid Swing
      lElbow: v.Vector3(-6, -7, 0),
      lHand: v.Vector3(-8, 5, 0),
      rElbow: v.Vector3(6, -7, 0),
      rHand: v.Vector3(8, 5, 0),
    );

    // POSE 3: Right Heel Strike (Right Leg Forward, Left Arm Forward) - Mirror of Pose 1
    poses[0.5] = _createPose(
      hip: v.Vector3(0, 2, 0),
      neck: v.Vector3(0, -13, 5),
      // Right Leg (Front)
      rKnee: v.Vector3(3, 15, 10),
      rFoot: v.Vector3(3, 25, 12),
      // Left Leg (Back)
      lKnee: v.Vector3(-3, 15, -5),
      lFoot: v.Vector3(-3, 20, -15),
      // Right Arm (Back)
      rElbow: v.Vector3(6, -5, -8),
      rHand: v.Vector3(8, 5, -12),
      // Left Arm (Front)
      lElbow: v.Vector3(-6, -5, 5),
      lHand: v.Vector3(-8, -8, 12),
    );

    // POSE 4: Mid-Stance Right (Left Leg Passing) - Mirror of Pose 2
    poses[0.75] = _createPose(
      hip: v.Vector3(0, 0, 0),
      neck: v.Vector3(0, -15, 5),
      // Right Leg (Supporting)
      rKnee: v.Vector3(3, 12, 5),
      rFoot: v.Vector3(3, 25, 0),
      // Left Leg (Passing)
      lKnee: v.Vector3(-3, 10, 15),
      lFoot: v.Vector3(-3, 20, 5),
      // Arms
      lElbow: v.Vector3(-6, -7, 0),
      lHand: v.Vector3(-8, 5, 0),
      rElbow: v.Vector3(6, -7, 0),
      rHand: v.Vector3(8, 5, 0),
    );

    // POSE 5: Loop Closure (Same as 0.0)
    poses[1.0] = poses[0.0]!;

    return StickmanClip(
      name: "Run",
      keyframes: _generateFramesFromPoses(poses, 30, style), // 30 frames for smoothness
      fps: 30,
      isLooping: true
    );
  }

  // --- 2. KICK ANIMATION (Linear Sequence) ---
  static StickmanClip generateKick(StickmanSkeleton? style) {
    final poses = <double, StickmanSkeleton>{};

    // 1. Stance (Neutral Fighting)
    poses[0.0] = _createPose(
      hip: v.Vector3(0, 5, 0),
      neck: v.Vector3(0, -10, 0),
      lFoot: v.Vector3(-5, 25, 5), lKnee: v.Vector3(-5, 15, 2),
      rFoot: v.Vector3(5, 25, -5), rKnee: v.Vector3(5, 15, -2),
      lHand: v.Vector3(-8, -5, 8), lElbow: v.Vector3(-6, -2, 4), // Guard up
      rHand: v.Vector3(8, -5, 5), rElbow: v.Vector3(6, -2, 2),
    );

    // 2. Chamber (Knee Up)
    poses[0.3] = _createPose(
      hip: v.Vector3(-2, 5, 0), // Shift weight left
      neck: v.Vector3(-2, -10, 0),
      lFoot: v.Vector3(-5, 25, 0), lKnee: v.Vector3(-5, 15, 2), // Pivot leg
      // Right leg knee up high
      rKnee: v.Vector3(5, -5, 10),
      rFoot: v.Vector3(5, 5, 5),
      // Arms balance
      lHand: v.Vector3(-8, -5, 10),
      rHand: v.Vector3(8, 0, -5),
    );

    // 3. Extension (Strike)
    poses[0.5] = _createPose(
      hip: v.Vector3(-5, 5, 0),
      neck: v.Vector3(-8, -10, 0), // Lean back
      lFoot: v.Vector3(-5, 25, 0),
      // Full extension
      rKnee: v.Vector3(5, -5, 15),
      rFoot: v.Vector3(5, -10, 25), // High kick forward
      // Arms counter balance
      lHand: v.Vector3(-8, -5, 10), // Guard face
      rHand: v.Vector3(10, 5, -10), // Swing back
    );

    // 4. Retract (Back to Chamber)
    poses[0.7] = poses[0.3]!;

    // 5. Land (Stance)
    poses[1.0] = poses[0.0]!;

    return StickmanClip(
      name: "Kick",
      keyframes: _generateFramesFromPoses(poses, 30, style),
      fps: 30,
      isLooping: false
    );
  }

  // --- 3. JUMP ANIMATION ---
  static StickmanClip generateJump(StickmanSkeleton? style) {
    final poses = <double, StickmanSkeleton>{};

    // 1. Neutral
    poses[0.0] = _createPose(
      hip: v.Vector3(0, 0, 0),
      lFoot: v.Vector3(-4, 25, 0), rFoot: v.Vector3(4, 25, 0),
    );

    // 2. Squat (Anticipation)
    poses[0.2] = _createPose(
      hip: v.Vector3(0, 15, 0), // Low
      neck: v.Vector3(0, 0, 5), // Lean forward
      lFoot: v.Vector3(-4, 25, 0), rFoot: v.Vector3(4, 25, 0),
      lKnee: v.Vector3(-4, 20, 10), rKnee: v.Vector3(4, 20, 10), // Knees forward
      lHand: v.Vector3(-10, 15, -5), rHand: v.Vector3(10, 15, -5), // Arms back
    );

    // 3. Apex (Air - Tuck)
    poses[0.5] = _createPose(
      hip: v.Vector3(0, -20, 0), // High in air
      neck: v.Vector3(0, -35, 0),
      lFoot: v.Vector3(-4, 0, -5), rFoot: v.Vector3(4, 0, -5), // Feet up
      lKnee: v.Vector3(-4, -10, 15), rKnee: v.Vector3(4, -10, 15), // Knees high
      lHand: v.Vector3(-10, -45, 10), rHand: v.Vector3(10, -45, 10), // Arms up!
      lElbow: v.Vector3(-8, -35, 0), rElbow: v.Vector3(8, -35, 0),
    );

    // 4. Impact (Squat)
    poses[0.8] = _createPose(
      hip: v.Vector3(0, 15, 0), // Low
      neck: v.Vector3(0, 0, 5),
      lFoot: v.Vector3(-4, 25, 0), rFoot: v.Vector3(4, 25, 0),
      lKnee: v.Vector3(-4, 20, 10), rKnee: v.Vector3(4, 20, 10),
      lHand: v.Vector3(-10, 10, 0), rHand: v.Vector3(10, 10, 0), // Stabilize
    );

    // 5. Recover (Neutral)
    poses[1.0] = poses[0.0]!;

    return StickmanClip(
      name: "Jump",
      keyframes: _generateFramesFromPoses(poses, 40, style),
      fps: 30,
      isLooping: false
    );
  }

  static StickmanClip generateEmpty(StickmanSkeleton? style) {
    List<StickmanKeyframe> frames = [];
    for(int i=0; i<30; i++) {
        StickmanSkeleton p = style != null ? style.clone() : StickmanSkeleton();
        frames.add(StickmanKeyframe(pose: p, frameIndex: i));
    }
    return StickmanClip(name: "Custom", keyframes: frames, fps: 30, isLooping: true);
  }
}
