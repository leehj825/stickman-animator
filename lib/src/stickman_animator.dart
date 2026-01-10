import 'dart:math';
import 'package:vector_math/vector_math_64.dart' as v;
import 'stickman_skeleton.dart';

enum WeaponType { none, sword, axe, bow }

/// 2. THE ANIMATOR: Calculates where the bones should be
class StickmanController {
  final StickmanSkeleton skeleton = StickmanSkeleton();

  // Configuration
  WeaponType weaponType;
  double scale;

  // State
  double _time = 0.0;
  double _runWeight = 0.0;
  double _facingAngle = 0.0;

  // Action State
  bool isAttacking = false;
  double _attackTimer = 0.0;

  StickmanController({this.scale = 1.0, this.weaponType = WeaponType.none});

  double get facingAngle => _facingAngle;

  void update(double dt, double velocityX, double velocityY) {
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

    _solveIK();
  }

  // Procedural Animation Solver (The "Math" part of your original render method)
  void _solveIK() {
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
