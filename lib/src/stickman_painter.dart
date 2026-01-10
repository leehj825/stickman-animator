import 'dart:math';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as v;
import 'stickman_animator.dart';

/// 3. THE PAINTER: Pure Flutter Rendering (No Flame logic here)
class StickmanPainter extends CustomPainter {
  final StickmanController controller;
  final Color color;

  StickmanPainter({required this.controller, this.color = Colors.white});

  @override
  void paint(Canvas canvas, Size size) {
    final skel = controller.skeleton;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0 * controller.scale
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()..color = color ..style = PaintingStyle.fill;

    // Center the canvas
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2); // Center drawing
    canvas.scale(controller.scale);

    // 3D Projection Helper
    Offset toScreen(v.Vector3 v) => Offset(v.x, v.y + (v.z * 0.3));

    // Draw Body
    canvas.drawLine(toScreen(skel.hip), toScreen(skel.neck), paint);

    // Draw Legs
    _drawLimb(canvas, toScreen(skel.lHip), toScreen(skel.lKnee), toScreen(skel.lFoot), paint);
    _drawLimb(canvas, toScreen(skel.rHip), toScreen(skel.rKnee), toScreen(skel.rFoot), paint);

    // Draw Arms
    _drawLimb(canvas, toScreen(skel.lShoulder), toScreen(skel.lElbow), toScreen(skel.lHand), paint);
    _drawLimb(canvas, toScreen(skel.rShoulder), toScreen(skel.rElbow), toScreen(skel.rHand), paint);

    // Head
    Offset headCenter = toScreen(skel.neck + v.Vector3(0, -8, 0));
    canvas.drawCircle(headCenter, 6, fillPaint);

    // Weapons
    if (controller.weaponType == WeaponType.sword) {
      _drawSword(canvas, toScreen(skel.rHand), controller.facingAngle, controller.isAttacking);
    }

    canvas.restore();
  }

  void _drawLimb(Canvas c, Offset start, Offset mid, Offset end, Paint p) {
    c.drawLine(start, mid, p);
    c.drawLine(mid, end, p);
  }

  void _drawSword(Canvas canvas, Offset handPos, double facing, bool attacking) {
      double angle = facing;
      if (attacking) angle += pi / 2;
      final Paint p = Paint()..color = Colors.white ..strokeWidth = 2;
      Offset end = handPos + Offset(cos(angle) * 20, sin(angle) * 5 - 20);
      canvas.drawLine(handPos, end, p);
      // Guard
      Offset guardCenter = handPos + Offset(cos(angle) * 5, sin(angle) * 1 - 5);
      canvas.drawLine(guardCenter - Offset(5,0), guardCenter + Offset(5,0), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
