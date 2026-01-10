import 'dart:math';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as v;
import 'stickman_skeleton.dart'; // Needed for StickmanNode
import 'stickman_animator.dart';

// Axis Mode Enum (Used in Editor too)
enum AxisMode { none, x, y, z }

/// 3. THE PAINTER: Pure Flutter Rendering (No Flame logic here)
class StickmanPainter extends CustomPainter {
  final StickmanController controller;
  final Color color;

  // View Parameters
  final double viewRotationX; // Pitch
  final double viewRotationY; // Yaw
  final double viewZoom;
  final Offset viewPan;

  // Editor State
  final String? selectedNodeId;
  final AxisMode axisMode;

  StickmanPainter({
    required this.controller,
    this.color = Colors.white,
    this.viewRotationX = 0.0,
    this.viewRotationY = 0.0,
    this.viewZoom = 1.0,
    this.viewPan = Offset.zero,
    this.selectedNodeId,
    this.axisMode = AxisMode.none,
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
    double sx = x2 * zoom;
    double sy = y2 * zoom;

    // 3. Center and Pan
    double cx = size.width / 2;
    double cy = size.height / 2;

    return Offset(cx + pan.dx + sx, cy + pan.dy + sy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final skel = controller.skeleton;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0 * viewZoom * controller.scale
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()..color = color ..style = PaintingStyle.fill;

    // Draw Ground Grid
    _drawGrid(canvas, size);

    // 3D Projection Helper instance
    Offset toScreen(v.Vector3 vec) => project(
      vec * controller.scale,
      size,
      viewRotationX,
      viewRotationY,
      viewZoom,
      viewPan
    );

    // Recursive Drawing
    void drawNode(StickmanNode node) {
      final start = toScreen(node.position);

      // Special Draw for Head Node
      if (node.id == 'head') {
        canvas.drawCircle(start, 6 * viewZoom * controller.scale, fillPaint);
      }

      for (var child in node.children) {
         final end = toScreen(child.position);
         canvas.drawLine(start, end, paint);
         drawNode(child);
      }
    }

    // Draw Bones
    drawNode(skel.root);

    // Legacy Support: Only if head node doesn't exist?
    // StickmanSkeleton now creates head node.
    // If we loaded old JSON, it might not have 'head'.
    // If 'head' is missing, draw legacy neck circle.
    if (!skel.nodes.containsKey('head') && skel.nodes.containsKey('neck')) {
      Offset headCenter = toScreen(skel.neck + v.Vector3(0, -8, 0));
      canvas.drawCircle(headCenter, 6 * viewZoom * controller.scale, fillPaint);
    }

    // Draw Axis Constraints (Dotted Line)
    if (selectedNodeId != null && axisMode != AxisMode.none) {
      final node = skel.nodes[selectedNodeId];
      if (node != null) {
        _drawAxisLine(canvas, size, node.position, axisMode, toScreen);
      }
    }
  }

  void _drawAxisLine(Canvas canvas, Size size, v.Vector3 pos, AxisMode mode, Offset Function(v.Vector3) projectFunc) {
     final p = Paint()
       ..style = PaintingStyle.stroke
       ..strokeWidth = 2.0;

     // Color convention: X=Red, Y=Green, Z=Blue
     v.Vector3 axisDir;
     if (mode == AxisMode.x) {
       p.color = Colors.red;
       axisDir = v.Vector3(1, 0, 0);
     } else if (mode == AxisMode.y) {
       p.color = Colors.green;
       axisDir = v.Vector3(0, 1, 0);
     } else { // Z
       p.color = Colors.blue;
       axisDir = v.Vector3(0, 0, 1);
     }

     // Draw a long line through 'pos' along 'axisDir'
     final length = 1000.0;
     final start3D = pos - axisDir * length;
     final end3D = pos + axisDir * length;

     final start2D = projectFunc(start3D);
     final end2D = projectFunc(end3D);

     _drawDottedLine(canvas, start2D, end2D, p);
  }

  void _drawDottedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const double dashWidth = 5;
    const double dashSpace = 5;
    double distance = (p2 - p1).distance;
    double dx = (p2.dx - p1.dx) / distance;
    double dy = (p2.dy - p1.dy) / distance;

    // Don't draw if distance is zero (axis perpendicular to view)
    if (distance == 0) return;

    double currentX = p1.dx;
    double currentY = p1.dy;

    double drawn = 0;
    while (drawn < distance) {
       canvas.drawLine(
         Offset(currentX, currentY),
         Offset(currentX + dx * dashWidth, currentY + dy * dashWidth),
         paint
       );
       currentX += dx * (dashWidth + dashSpace);
       currentY += dy * (dashWidth + dashSpace);
       drawn += dashWidth + dashSpace;
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    const int steps = 10;
    const double range = 100.0;
    const double stepSize = range * 2 / steps;

    Offset p(double x, double z) => project(
      v.Vector3(x, 25, z) * controller.scale,
      size,
      viewRotationX,
      viewRotationY,
      viewZoom,
      viewPan
    );

    for (int i = 0; i <= steps; i++) {
      double v = -range + i * stepSize;
      canvas.drawLine(p(-range, v), p(range, v), gridPaint);
      canvas.drawLine(p(v, -range), p(v, range), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant StickmanPainter oldDelegate) {
    return oldDelegate.viewRotationX != viewRotationX ||
           oldDelegate.viewRotationY != viewRotationY ||
           oldDelegate.viewZoom != viewZoom ||
           oldDelegate.viewPan != viewPan ||
           oldDelegate.controller != controller ||
           oldDelegate.selectedNodeId != selectedNodeId ||
           oldDelegate.axisMode != axisMode;
  }
}
