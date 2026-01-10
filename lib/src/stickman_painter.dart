import 'dart:math';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as v;
import 'stickman_skeleton.dart'; // Needed for StickmanNode
import 'stickman_animator.dart';

/// 3. THE PAINTER: Pure Flutter Rendering (No Flame logic here)
class StickmanPainter extends CustomPainter {
  final StickmanController controller;
  final Color color;

  // View Parameters
  final double viewRotationX; // Pitch
  final double viewRotationY; // Yaw
  final double viewZoom;
  final Offset viewPan;

  StickmanPainter({
    required this.controller,
    this.color = Colors.white,
    this.viewRotationX = 0.0,
    this.viewRotationY = 0.0,
    this.viewZoom = 1.0,
    this.viewPan = Offset.zero,
  });

  // Public helper so Editor can use exact same projection
  // Applies Rotation -> Scale -> Pan -> Center Offset
  static Offset project(
      v.Vector3 point,
      Size size,
      double rotX,
      double rotY,
      double zoom,
      Offset pan)
  {
    // 1. Rotation (Orbit around 0,0,0)
    // Rotate Y (Yaw)
    double x1 = point.x * cos(rotY) - point.z * sin(rotY);
    double z1 = point.x * sin(rotY) + point.z * cos(rotY);
    double y1 = point.y;

    // Rotate X (Pitch)
    double y2 = y1 * cos(rotX) - z1 * sin(rotX);
    double z2 = y1 * sin(rotX) + z1 * cos(rotX);
    double x2 = x1;

    // 2. Scale (Zoom) + Model Scale
    // We treat z2 as depth but for orthographic drawing we just drop it
    // or use it for sorting (not needed for wireframe lines).
    // Note: Standard canvas coords: X right, Y down.
    // Our 3D model: Y? Stickman seems to use Y down? (Head -25, Hip 0).
    // Let's assume standard Flutter coord system.

    double sx = x2 * zoom;
    double sy = y2 * zoom;

    // 3. Center and Pan
    // Center of canvas
    double cx = size.width / 2;
    double cy = size.height / 2;

    return Offset(cx + pan.dx + sx, cy + pan.dy + sy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Note: We don't use canvas.scale/translate directly because we want full control over 3D rotation projection.
    // But we could use Matrix4 for rotation if we wanted.
    // Manual projection is fine for wireframe.

    final skel = controller.skeleton;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0 * viewZoom * controller.scale // Adjust stroke with zoom? Maybe keep constant or scale? User said "larger", usually means visual scale.
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()..color = color ..style = PaintingStyle.fill;

    // Draw Ground Grid
    _drawGrid(canvas, size);

    // 3D Projection Helper instance
    Offset toScreen(v.Vector3 vec) => project(
      vec * controller.scale, // Apply model scale here
      size,
      viewRotationX,
      viewRotationY,
      viewZoom,
      viewPan
    );

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
      // Offset headCenter = toScreen(skel.neck + v.Vector3(0, -8, 0));
      // Need to project the head position after adding offset in 3D
      Offset headCenter = toScreen(skel.neck + v.Vector3(0, -8, 0));
      canvas.drawCircle(headCenter, 6 * viewZoom * controller.scale, fillPaint);
    }

    // Weapons (Legacy logic)
    if (controller.weaponType == WeaponType.sword && skel.nodes.containsKey('rHand')) {
      // _drawSword needs updating for 3D rotation, but it uses 2D offsets logic.
      // It's hard to make 2D sprite logic work in 3D rotation easily.
      // We will skip strict 3D correctness for the sword drawing for now
      // or try to project start/end.
      // _drawSword(canvas, toScreen(skel.rHand), controller.facingAngle, controller.isAttacking);
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Grid size: -100 to 100
    const int steps = 10;
    const double range = 100.0;
    const double stepSize = range * 2 / steps;

    Offset p(double x, double z) => project(
      v.Vector3(x, 25, z) * controller.scale, // Ground at Y=25 (Stickman feet approx)
      size,
      viewRotationX,
      viewRotationY,
      viewZoom,
      viewPan
    );

    for (int i = 0; i <= steps; i++) {
      double v = -range + i * stepSize;
      // Z-lines (vary X)
      canvas.drawLine(p(-range, v), p(range, v), gridPaint);
      // X-lines (vary Z)
      canvas.drawLine(p(v, -range), p(v, range), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant StickmanPainter oldDelegate) {
    return oldDelegate.viewRotationX != viewRotationX ||
           oldDelegate.viewRotationY != viewRotationY ||
           oldDelegate.viewZoom != viewZoom ||
           oldDelegate.viewPan != viewPan ||
           oldDelegate.controller != controller;
  }
}
