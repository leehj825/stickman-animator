import 'dart:math';
import 'package:vector_math/vector_math_64.dart' as v;
import 'stickman_skeleton.dart';

class StickmanExporter {
  /// Generates a Wavefront OBJ string from the skeleton
  static String generateObjString(StickmanSkeleton skeleton) {
    final StringBuffer buffer = StringBuffer();
    int vertexOffset = 1;

    // Header
    buffer.writeln("# Stickman 3D OBJ Export");
    buffer.writeln("o Stickman");

    // Helper to add a box (bone)
    // Returns the number of vertices added
    int addBox(v.Vector3 start, v.Vector3 end, double thickness) {
      // Calculate bone vector
      final direction = end - start;
      final length = direction.length;

      if (length < 0.001) return 0; // Ignore zero length bones

      final normalizedDir = direction.normalized();

      // Create a local coordinate system for the box
      // We need a generic "up" vector to compute the cross product
      v.Vector3 up = v.Vector3(0, 1, 0);
      if ((normalizedDir.dot(up)).abs() > 0.9) {
        up = v.Vector3(0, 0, 1); // Switch up vector if parallel
      }

      final right = normalizedDir.cross(up).normalized();
      final finalUp = right.cross(normalizedDir).normalized();

      final halfThickness = thickness / 2;

      // Local offsets for a square cross-section box
      // 4 corners around the start point and 4 around the end point
      final p1 = start + (right * halfThickness) + (finalUp * halfThickness);
      final p2 = start - (right * halfThickness) + (finalUp * halfThickness);
      final p3 = start - (right * halfThickness) - (finalUp * halfThickness);
      final p4 = start + (right * halfThickness) - (finalUp * halfThickness);

      final p5 = end + (right * halfThickness) + (finalUp * halfThickness);
      final p6 = end - (right * halfThickness) + (finalUp * halfThickness);
      final p7 = end - (right * halfThickness) - (finalUp * halfThickness);
      final p8 = end + (right * halfThickness) - (finalUp * halfThickness);

      // Write Vertices
      for (var p in [p1, p2, p3, p4, p5, p6, p7, p8]) {
        buffer.writeln("v ${p.x} ${p.y} ${p.z}");
      }

      // Write Faces (Quads)
      // Cube has 6 faces
      // Indices are 1-based, relative to current file, but we track offset
      // Front: 1 2 3 4 (Start Cap) - winding might be inside, let's check
      // Actually typical box winding:
      // Side 1: 1 5 6 2
      // Side 2: 2 6 7 3
      // Side 3: 3 7 8 4
      // Side 4: 4 8 5 1
      // Cap 1 (Start): 4 3 2 1
      // Cap 2 (End): 5 6 7 8

      final o = vertexOffset;
      // Sides
      buffer.writeln("f ${o} ${o+4} ${o+5} ${o+1}");
      buffer.writeln("f ${o+1} ${o+5} ${o+6} ${o+2}");
      buffer.writeln("f ${o+2} ${o+6} ${o+7} ${o+3}");
      buffer.writeln("f ${o+3} ${o+7} ${o+4} ${o}");

      // Caps
      buffer.writeln("f ${o+3} ${o+2} ${o+1} ${o}");
      buffer.writeln("f ${o+4} ${o+7} ${o+6} ${o+5}");

      return 8;
    }

    // Helper to add a cube (head)
    int addCube(v.Vector3 center, double radius) {
      // Just an AABB centered at 'center' with side length = radius * 2 (or radius? "size must match headRadius")
      // User said "Head: Generate a simple Cube... Critical: The size must match skeleton.headRadius."
      // Assuming 'radius' implies half-width. So cube is center +/- radius.

      final r = radius;
      final x = center.x;
      final y = center.y;
      final z = center.z;

      // Vertices
      buffer.writeln("v ${x+r} ${y+r} ${z+r}"); // 1: +++
      buffer.writeln("v ${x-r} ${y+r} ${z+r}"); // 2: -++
      buffer.writeln("v ${x-r} ${y-r} ${z+r}"); // 3: --+
      buffer.writeln("v ${x+r} ${y-r} ${z+r}"); // 4: +-+
      buffer.writeln("v ${x+r} ${y+r} ${z-r}"); // 5: ++-
      buffer.writeln("v ${x-r} ${y+r} ${z-r}"); // 6: -+-
      buffer.writeln("v ${x-r} ${y-r} ${z-r}"); // 7: ---
      buffer.writeln("v ${x+r} ${y-r} ${z-r}"); // 8: +--

      final o = vertexOffset;

      // Front (Z+)
      buffer.writeln("f ${o} ${o+1} ${o+2} ${o+3}");
      // Back (Z-)
      buffer.writeln("f ${o+7} ${o+6} ${o+5} ${o+4}");
      // Top (Y+)
      buffer.writeln("f ${o+4} ${o+5} ${o+1} ${o}");
      // Bottom (Y-)
      buffer.writeln("f ${o+3} ${o+2} ${o+6} ${o+7}");
      // Right (X+)
      buffer.writeln("f ${o+4} ${o} ${o+3} ${o+7}");
      // Left (X-)
      buffer.writeln("f ${o+1} ${o+5} ${o+6} ${o+2}");

      return 8;
    }

    // Traverse and Generate
    void traverse(StickmanNode node) {
      if (node.id == 'head') {
        vertexOffset += addCube(node.position, skeleton.headRadius);
      } else {
        // Draw connections to children as bones
        // BUT 'head' is a child of 'neck'. We treat the connection neck->head as a neck bone?
        // Or do we just draw bones for every child connection?
        // Usually stickman is drawn as lines between parent and child.
        // Except for the head node itself which is a volume.

        for (var child in node.children) {
          // If child is head, we still draw a line to it (the neck)?
          // User said: "Limbs: Generate a 4-sided Cylinder or Box connecting each joint (e.g., Hip to Knee)."
          // "Head: Generate a simple Cube at the neck position." -> Wait, "at the neck position"?
          // Or "at the head node position"?
          // Original request: "Head: Generate a simple Cube at the neck position."
          // Checking memory/context: "The 'head' is explicitly implemented as a child 'StickmanNode' of the 'neck'..."
          // So 'head' node has a position.
          // If the cube is at 'neck', it conflicts with the neck node.
          // Likely means "at the head's position" (which represents the head).
          // Re-reading carefully: "Head: Generate a simple Cube at the neck position."
          // This phrasing is ambiguous. "Head... at the neck position".
          // In standard stickman, the head is a circle attached to the neck.
          // I will assume it means "Generate a Cube for the Head node".

          // Also check if we draw a bone to the head. Usually a neck line exists.
          // If I draw a bone from Neck -> Head, that's the neck.

          // Let's draw bones to all children.
          // Note: If child is 'head', the bone (neck) goes to the center of the head.

          vertexOffset += addBox(node.position, child.position, skeleton.strokeWidth);
          traverse(child);
        }
      }
    }

    // Start traversal from root
    traverse(skeleton.root);

    return buffer.toString();
  }
}
