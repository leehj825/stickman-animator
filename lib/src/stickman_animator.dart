import 'dart:math';
import 'package:vector_math/vector_math_64.dart' as v;
import 'stickman_skeleton.dart';

enum WeaponType { none, sword, axe, bow }
enum StickmanState { animating, ragdoll }

/// 2. THE ANIMATOR: Calculates where the bones should be
class StickmanController {
  final StickmanSkeleton skeleton = StickmanSkeleton();
  StickmanState state = StickmanState.animating;

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

  StickmanController({this.scale = 1.0, this.weaponType = WeaponType.none});

  double get facingAngle => _facingAngle;

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

    _solveProceduralAnimation();
  }

  // Procedural Animation Solver (The "Math" part of your original render method)
  void _solveProceduralAnimation() {
    // --- Local Space Calculation ---
    // 1. Spine & Breathing
    skeleton.hip.setValues(0, 0, 0);
    double breath = sin(_time * 0.5) * 1.0;
    double bounce = breath * (1 - _runWeight) + (sin(_time)).abs() * 3.0 * _runWeight;
    skeleton.neck.setValues(0, -25 + bounce, 0);

    // 2. Shoulders & Hips (Relative to body)
    skeleton.lShoulder = skeleton.neck.clone();
    skeleton.rShoulder = skeleton.neck.clone();
    skeleton.lHip = skeleton.hip.clone();
    skeleton.rHip = skeleton.hip.clone();

    // 3. Limbs (Run Cycle)
    double legSwing = sin(_time) * 0.8 * _runWeight;
    double armSwing = cos(_time) * 0.8 * _runWeight;

    // Helper to rotate local points
    v.Vector3 rotateX(v.Vector3 point, double angle) {
      final rot = v.Matrix3.rotationX(angle);
      return rot.transform(point);
    }

    // Legs
    skeleton.lKnee = rotateX(v.Vector3(-3, 12, 0), legSwing) + skeleton.lHip;
    skeleton.rKnee = rotateX(v.Vector3(3, 12, 0), -legSwing) + skeleton.rHip;
    skeleton.lFoot = rotateX(v.Vector3(-3, 12, 0), legSwing + 0.2) + skeleton.lKnee;
    skeleton.rFoot = rotateX(v.Vector3(3, 12, 0), -legSwing + 0.2) + skeleton.rKnee;

    // Arms
    double lArmAngle = -armSwing;
    double rArmAngle = armSwing;

    // Weapon logic override
    if (isAttacking) {
      rArmAngle = -1.5;
    } else if (weaponType == WeaponType.bow) {
      lArmAngle = -1.5;
      rArmAngle = -1.5;
    } else if (weaponType != WeaponType.none) {
      rArmAngle = -0.5;
    }

    skeleton.lElbow = rotateX(v.Vector3(-6, 10, 0), lArmAngle) + skeleton.lShoulder;
    skeleton.rElbow = rotateX(v.Vector3(6, 10, 0), rArmAngle) + skeleton.rShoulder;

    skeleton.lHand = rotateX(v.Vector3(0, 10, 0), lArmAngle - 0.3) + skeleton.lElbow;
    skeleton.rHand = rotateX(v.Vector3(0, 10, 0), rArmAngle - 0.3) + skeleton.rElbow;

    // Attack Punch Lunge
    if (isAttacking) {
       double progress = sin((_attackTimer / 0.3) * pi);
       skeleton.rHand.z += progress * 15;
       skeleton.rHand.y -= progress * 5;
    }

    // --- Global Rotation (Y-Axis) ---
    final rotY = v.Matrix3.rotationY(_facingAngle);
    // Apply to all points
    List<v.Vector3> points = [
      skeleton.hip, skeleton.neck, skeleton.lShoulder, skeleton.rShoulder,
      skeleton.lHip, skeleton.rHip, skeleton.lKnee, skeleton.rKnee,
      skeleton.lFoot, skeleton.rFoot, skeleton.lElbow, skeleton.rElbow,
      skeleton.lHand, skeleton.rHand
    ];

    for (var p in points) {
      p.setFrom(rotY.transform(p));
    }
  }
}

/// 3. PHYSICS ENGINE (Verlet Integration)
class _RagdollPoint {
  v.Vector3 pos;
  v.Vector3 oldPos;
  bool isPinned; // Used if we want to pin the head or feet

  _RagdollPoint(v.Vector3 initialPos, {this.isPinned = false})
      : pos = initialPos.clone(),
        oldPos = initialPos.clone();
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

  // Map skeleton parts to physics points
  late _RagdollPoint hip, neck, lS, rS, lH, rH, lK, rK, lF, rF, lE, rE, lHa, rHa;

  _RagdollPhysics(StickmanSkeleton skel) {
    // 1. Create Points from current skeleton positions
    _RagdollPoint mk(v.Vector3 vec) {
      var p = _RagdollPoint(vec);
      points.add(p);
      return p;
    }

    hip = mk(skel.hip); neck = mk(skel.neck);
    lS = mk(skel.lShoulder); rS = mk(skel.rShoulder);
    lH = mk(skel.lHip); rH = mk(skel.rHip);
    lK = mk(skel.lKnee); rK = mk(skel.rKnee);
    lF = mk(skel.lFoot); rF = mk(skel.rFoot);
    lE = mk(skel.lElbow); rE = mk(skel.rElbow);
    lHa = mk(skel.lHand); rHa = mk(skel.rHand);

    // 2. Create Sticks (Constraints) - Defines the "Body Shape"
    void link(_RagdollPoint a, _RagdollPoint b) => sticks.add(_StickConstraint(a, b));

    // Spine
    link(hip, neck);
    // Shoulders (Connect to Neck)
    link(neck, lS); link(neck, rS);
    // Hips (Connect to Hip center)
    link(hip, lH); link(hip, rH);
    // Arms
    link(lS, lE); link(lE, lHa);
    link(rS, rE); link(rE, rHa);
    // Legs
    link(lH, lK); link(lK, lF);
    link(rH, rK); link(rK, rF);

    // Optional: Cross-links for stability (prevents collapsing too easily)
    link(lS, rS); // Shoulder width
    link(lH, rH); // Hip width
    link(lS, lH); // Left Torso side
    link(rS, rH); // Right Torso side
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
    skel.hip.setFrom(hip.pos); skel.neck.setFrom(neck.pos);
    skel.lShoulder.setFrom(lS.pos); skel.rShoulder.setFrom(rS.pos);
    skel.lHip.setFrom(lH.pos); skel.rHip.setFrom(rH.pos);
    skel.lKnee.setFrom(lK.pos); skel.rKnee.setFrom(rK.pos);
    skel.lFoot.setFrom(lF.pos); skel.rFoot.setFrom(rF.pos);
    skel.lElbow.setFrom(lE.pos); skel.rElbow.setFrom(rE.pos);
    skel.lHand.setFrom(lHa.pos); skel.rHand.setFrom(rHa.pos);
  }
}
