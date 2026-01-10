import 'dart:math';
import 'package:vector_math/vector_math_64.dart' as v;
import 'stickman_skeleton.dart';

enum WeaponType { none, sword, axe, bow }
enum StickmanState { animating, ragdoll }

/// Interface for movement strategies
abstract class MotionStrategy {
  void update(double dt, StickmanController controller);
}

/// A strategy that does nothing, allowing manual manipulation of the skeleton.
class ManualMotionStrategy implements MotionStrategy {
  @override
  void update(double dt, StickmanController controller) {
    // No-op: The skeleton is updated manually (e.g. by the Editor)
  }
}

/// The existing procedural sine-wave/running logic
class ProceduralMotionStrategy implements MotionStrategy {
  @override
  void update(double dt, StickmanController controller) {
    // --- Local Space Calculation ---
    // 1. Spine & Breathing
    // NOTE: We are setting values via the compatibility setters in StickmanSkeleton
    controller.skeleton.hip.setValues(0, 0, 0);
    double breath = sin(controller.time * 0.5) * 1.0;
    double bounce = breath * (1 - controller.runWeight) + (sin(controller.time)).abs() * 3.0 * controller.runWeight;
    controller.skeleton.neck.setValues(0, -25 + bounce, 0);

    // 2. Shoulders & Hips (Relative to body)
    controller.skeleton.lShoulder = controller.skeleton.neck.clone();
    controller.skeleton.rShoulder = controller.skeleton.neck.clone();
    controller.skeleton.lHip = controller.skeleton.hip.clone();
    controller.skeleton.rHip = controller.skeleton.hip.clone();

    // 3. Limbs (Run Cycle)
    double legSwing = sin(controller.time) * 0.8 * controller.runWeight;
    double armSwing = cos(controller.time) * 0.8 * controller.runWeight;

    // Helper to rotate local points
    v.Vector3 rotateX(v.Vector3 point, double angle) {
      final rot = v.Matrix3.rotationX(angle);
      return rot.transform(point);
    }

    // Legs
    controller.skeleton.lKnee = rotateX(v.Vector3(-3, 12, 0), legSwing) + controller.skeleton.lHip;
    controller.skeleton.rKnee = rotateX(v.Vector3(3, 12, 0), -legSwing) + controller.skeleton.rHip;
    controller.skeleton.lFoot = rotateX(v.Vector3(-3, 12, 0), legSwing + 0.2) + controller.skeleton.lKnee;
    controller.skeleton.rFoot = rotateX(v.Vector3(3, 12, 0), -legSwing + 0.2) + controller.skeleton.rKnee;

    // Arms
    double lArmAngle = -armSwing;
    double rArmAngle = armSwing;

    // Weapon logic override
    if (controller.isAttacking) {
      rArmAngle = -1.5;
    } else if (controller.weaponType == WeaponType.bow) {
      lArmAngle = -1.5;
      rArmAngle = -1.5;
    } else if (controller.weaponType != WeaponType.none) {
      rArmAngle = -0.5;
    }

    controller.skeleton.lElbow = rotateX(v.Vector3(-6, 10, 0), lArmAngle) + controller.skeleton.lShoulder;
    controller.skeleton.rElbow = rotateX(v.Vector3(6, 10, 0), rArmAngle) + controller.skeleton.rShoulder;

    controller.skeleton.lHand = rotateX(v.Vector3(0, 10, 0), lArmAngle - 0.3) + controller.skeleton.lElbow;
    controller.skeleton.rHand = rotateX(v.Vector3(0, 10, 0), rArmAngle - 0.3) + controller.skeleton.rElbow;

    // Attack Punch Lunge
    if (controller.isAttacking) {
       double progress = sin((controller.attackTimer / 0.3) * pi);
       controller.skeleton.rHand.z += progress * 15;
       controller.skeleton.rHand.y -= progress * 5;
    }

    // --- Global Rotation (Y-Axis) ---
    final rotY = v.Matrix3.rotationY(controller.facingAngle);

    // Apply to all points
    // Using traverse to support any structure, or just the main ones?
    // Procedural strategy specifically positions the standard skeleton.
    // If we have extra nodes, they won't be animated procedurally unless they are children of these nodes
    // and we propagate rotation (which we don't do here, we set absolute positions).
    // So for now, we just rotate the standard points.

    // Actually, if we rotate the parent, the children should move?
    // The current logic calculates absolute positions for every standard bone.
    // So if I add a child to lHand, it won't move unless I manually move it relative to lHand.
    // But since `StickmanSkeleton` is just a data container, and this strategy overwrites values,
    // extra nodes will stay at (0,0,0) or wherever they were initialized unless updated.

    // Ideally, we should apply rotation to the whole hierarchy if we want "Global Rotation".
    // But existing logic iterates a specific list. Let's keep it safe.

    List<v.Vector3> points = controller.skeleton.allPoints; // Uses recursive fetch now

    for (var p in points) {
      p.setFrom(rotY.transform(p));
    }
  }
}

/// Interpolates the skeleton toward a target pose
class PoseMotionStrategy implements MotionStrategy {
  final StickmanSkeleton targetPose;

  PoseMotionStrategy(this.targetPose);

  @override
  void update(double dt, StickmanController controller) {
    // Interpolate towards the target pose
    double t = (dt * 5.0).clamp(0.0, 1.0);
    controller.skeleton.lerp(targetPose, t);
  }
}


/// 2. THE ANIMATOR: Calculates where the bones should be
class StickmanController {
  final StickmanSkeleton skeleton = StickmanSkeleton();
  StickmanState state = StickmanState.animating;

  late MotionStrategy _activeStrategy;

  // Configuration
  WeaponType weaponType;
  double scale;

  // Animation State
  double _time = 0.0;
  double _runWeight = 0.0;
  double _facingAngle = 0.0;

  // Action State
  bool isAttacking = false;
  double _attackTimer = 0.0;

  // Physics State
  _RagdollPhysics? _ragdoll;

  StickmanController({this.scale = 1.0, this.weaponType = WeaponType.none}) {
    _activeStrategy = ProceduralMotionStrategy();
  }

  // Getters for Strategy to access private fields if they were private
  double get time => _time;
  double get runWeight => _runWeight;
  double get facingAngle => _facingAngle;
  double get attackTimer => _attackTimer;

  void setStrategy(MotionStrategy strategy) {
    _activeStrategy = strategy;
  }

  void die() {
    if (state == StickmanState.ragdoll) return;
    state = StickmanState.ragdoll;

    // Initialize physics with current bone positions
    _ragdoll = _RagdollPhysics(skeleton);

    // Apply an initial "Impact force" (e.g., knocked backward)
    v.Vector3 impact = v.Vector3(sin(_facingAngle) * -10, -10, cos(_facingAngle) * -10);
    for (var p in _ragdoll!.points) {
      p.pos.add(impact); // Move position slightly so next frame calculates velocity
    }
  }

  void respawn() {
    state = StickmanState.animating;
    _ragdoll = null;
    _time = 0;
  }

  void update(double dt, double velocityX, double velocityY) {
    if (state == StickmanState.ragdoll) {
      _ragdoll?.update(dt);
      _ragdoll?.applyToSkeleton(skeleton);
      return;
    }

    // --- STANDARD ANIMATION LOGIC ---
    _time += dt * 10;

    // Speed & Direction Logic
    double speed = sqrt(velocityX * velocityX + velocityY * velocityY);
    double targetWeight = speed > 10 ? 1.0 : 0.0;
    _runWeight += (targetWeight - _runWeight) * dt * 5;

    if (speed > 10) {
      double targetAngle = atan2(velocityY, velocityX) + pi / 2;
      double diff = targetAngle - _facingAngle;
      // Normalize angle
      while (diff < -pi) diff += 2 * pi;
      while (diff > pi) diff -= 2 * pi;
      _facingAngle += diff * dt * 10;
    }

    // Attack Timer
    if (isAttacking) {
      _attackTimer += dt;
      if (_attackTimer > 0.3) {
        isAttacking = false;
        _attackTimer = 0.0;
      }
    }

    _activeStrategy.update(dt, this);
  }
}

/// 3. PHYSICS ENGINE (Verlet Integration)
class _RagdollPoint {
  StickmanNode? node; // Link back to node
  v.Vector3 pos;
  v.Vector3 oldPos;
  bool isPinned;

  _RagdollPoint(this.pos, {this.isPinned = false, this.node})
      : oldPos = pos.clone();
}

class _StickConstraint {
  _RagdollPoint p1;
  _RagdollPoint p2;
  double length;

  _StickConstraint(this.p1, this.p2) : length = p1.pos.distanceTo(p2.pos);
}

class _RagdollPhysics {
  List<_RagdollPoint> points = [];
  List<_StickConstraint> sticks = [];

  // Used for cross-linking specific parts if they exist
  _RagdollPoint? hip, lS, rS, lH, rH;

  _RagdollPhysics(StickmanSkeleton skel) {
    final pointMap = <String, _RagdollPoint>{};

    // 1. Create Points recursively
    void buildPoints(StickmanNode node) {
      var p = _RagdollPoint(node.position, node: node); // Use reference to position? No, separate physics state.
      // Actually RagdollPoint copies the vector.
      points.add(p);
      pointMap[node.id] = p;

      // Assign special points for cross-linking
      if (node.id == 'hip') hip = p;
      if (node.id == 'lShoulder') lS = p;
      if (node.id == 'rShoulder') rS = p;
      if (node.id == 'lHip') lH = p;
      if (node.id == 'rHip') rH = p;

      for (var c in node.children) {
        buildPoints(c);
      }
    }
    buildPoints(skel.root);

    // 2. Create Sticks (Constraints) - Defines the "Body Shape"
    void link(_RagdollPoint a, _RagdollPoint b) => sticks.add(_StickConstraint(a, b));

    // Automatically link parents to children
    void buildConstraints(StickmanNode node) {
      if (!pointMap.containsKey(node.id)) return;
      var p1 = pointMap[node.id]!;

      for (var c in node.children) {
         if (pointMap.containsKey(c.id)) {
           link(p1, pointMap[c.id]!);
           buildConstraints(c);
         }
      }
    }
    buildConstraints(skel.root);

    // Optional: Cross-links for stability (prevents collapsing too easily)
    // Only if the specific nodes exist
    if (lS != null && rS != null) link(lS!, rS!); // Shoulder width
    if (lH != null && rH != null) link(lH!, rH!); // Hip width
    if (lS != null && lH != null) link(lS!, lH!); // Left Torso side
    if (rS != null && rH != null) link(rS!, rH!); // Right Torso side
    // Hip to neck is handled by tree traversal (hip -> neck)
  }

  void update(double dt) {
    // A. Apply Forces (Gravity)
    v.Vector3 gravity = v.Vector3(0, 500, 0); // Positive Y is down

    for (var p in points) {
      if (p.isPinned) continue;

      // Verlet Step: pos = pos + (pos - oldPos) + acc * dt * dt
      v.Vector3 velocity = p.pos - p.oldPos;
      p.oldPos = p.pos.clone(); // Save current as old

      // Apply Friction/Damping (0.99)
      velocity.scale(0.98);

      p.pos.add(velocity);
      p.pos.add(gravity * (dt * dt));

      // Floor Collision (Assuming Floor Y = 25 relative to hip origin)
      double floorY = 25.0;
      if (p.pos.y > floorY) {
        p.pos.y = floorY;
        // Simple friction on floor
        double friction = 0.5;
        v.Vector3 slidingVel = p.pos - p.oldPos;
        slidingVel.x *= friction;
        slidingVel.z *= friction;
        p.oldPos = p.pos - slidingVel;
      }
    }

    // B. Solve Constraints (Iterate 3 times for stiffness)
    for (int i = 0; i < 3; i++) {
      for (var stick in sticks) {
        v.Vector3 delta = stick.p2.pos - stick.p1.pos;
        double currentLen = delta.length;
        if (currentLen == 0) continue; // Prevent div/0

        double difference = (currentLen - stick.length) / currentLen;
        v.Vector3 correction = delta * (0.5 * difference); // Each point moves half the error

        if (!stick.p1.isPinned) stick.p1.pos.add(correction);
        if (!stick.p2.isPinned) stick.p2.pos.sub(correction);
      }
    }
  }

  // Copy simulated positions back to the visual skeleton
  void applyToSkeleton(StickmanSkeleton skel) {
    // Because we link points to nodes via ID (implicit) or reference?
    // In constructor we iterated skel.root.
    // We stored `node` in RagdollPoint.
    for(var p in points) {
      if(p.node != null) {
        p.node!.position.setFrom(p.pos);
      }
    }
  }
}
