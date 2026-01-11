import 'stickman_skeleton.dart';

/// Represents a single frame in an animation clip.
class StickmanKeyframe {
  final StickmanSkeleton pose;
  final int frameIndex;

  StickmanKeyframe({required this.pose, required this.frameIndex});

  Map<String, dynamic> toJson() {
    return {
      'pose': pose.toJson(),
      'frameIndex': frameIndex,
    };
  }

  factory StickmanKeyframe.fromJson(Map<String, dynamic> json) {
    return StickmanKeyframe(
      pose: StickmanSkeleton.fromJson(json['pose']),
      frameIndex: json['frameIndex'] as int,
    );
  }
}

/// Represents a sequence of keyframes.
class StickmanClip {
  final String name;
  final List<StickmanKeyframe> keyframes;
  final double fps;
  final bool isLooping;

  StickmanClip({
    required this.name,
    required this.keyframes,
    this.fps = 30.0,
    this.isLooping = true,
  });

  /// Creates a clip with [length] frames, all initialized to the default pose.
  factory StickmanClip.empty(int length) {
    final frames = List.generate(length, (index) {
      return StickmanKeyframe(pose: StickmanSkeleton(), frameIndex: index);
    });
    return StickmanClip(name: "New Animation", keyframes: frames);
  }

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

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'keyframes': keyframes.map((k) => k.toJson()).toList(),
      'fps': fps,
      'isLooping': isLooping,
    };
  }

  factory StickmanClip.fromJson(Map<String, dynamic> json) {
    var keyframesList = (json['keyframes'] as List)
        .map((k) => StickmanKeyframe.fromJson(k))
        .toList();

    return StickmanClip(
      name: json['name'] as String,
      keyframes: keyframesList,
      fps: (json['fps'] as num).toDouble(),
      isLooping: json['isLooping'] as bool? ?? true,
    );
  }
}
