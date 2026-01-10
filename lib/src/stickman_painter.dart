import 'dart:math';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as v;
import 'stickman_skeleton.dart'; // Needed for StickmanNode
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

    // Recursive Drawing
    void drawNode(StickmanNode node) {
      final start = toScreen(node.position);

      for (var child in node.children) {
         final end = toScreen(child.position);
         canvas.drawLine(start, end, paint);
         drawNode(child);
      }
    }

    // Draw Bones
    drawNode(skel.root);

    // Legacy: Head (Draw at neck position)
    if (skel.nodes.containsKey('neck')) {
      Offset headCenter = toScreen(skel.neck + v.Vector3(0, -8, 0));
      canvas.drawCircle(headCenter, 6, fillPaint);
    }

    // Weapons (Legacy logic)
    if (controller.weaponType == WeaponType.sword && skel.nodes.containsKey('rHand')) {
      _drawSword(canvas, toScreen(skel.rHand), controller.facingAngle, controller.isAttacking);
    }

    canvas.restore();
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
