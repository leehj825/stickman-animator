import 'stickman_skeleton.dart';

/// Represents a single frame in an animation clip.
class StickmanKeyframe {
  final StickmanSkeleton pose;
  final int frameIndex;

  StickmanKeyframe({required this.pose, required this.frameIndex});
}

/// Represents a sequence of keyframes.
class StickmanClip {
  final String name;
  final List<StickmanKeyframe> keyframes;
  final double fps;

  StickmanClip({
    required this.name,
    required this.keyframes,
    this.fps = 30.0,
  });

  /// Returns the keyframe at the specified index.
  /// If index is out of bounds, returns the last or first frame (clamped).
  StickmanKeyframe getFrame(int index) {
    if (keyframes.isEmpty) {
      // Return a default pose if empty
      return StickmanKeyframe(pose: StickmanSkeleton(), frameIndex: 0);
    }
    int clampedIndex = index.clamp(0, keyframes.length - 1);
    return keyframes[clampedIndex];
  }

  /// Updates the pose at the specified index.
  void updateFrame(int index, StickmanSkeleton newPose) {
    if (index < 0 || index >= keyframes.length) return;

    // We replace the keyframe with a new one containing the cloned pose
    // to ensure we don't accidentally share mutable state reference issues later
    keyframes[index] = StickmanKeyframe(
      pose: newPose.clone(),
      frameIndex: index,
    );
  }

  /// Total number of frames in the clip
  int get frameCount => keyframes.length;
}
