import 'package:flutter_test/flutter_test.dart';
import 'package:stickman_3d/stickman_3d.dart';
import 'package:vector_math/vector_math_64.dart' as v;

void main() {
  test('StickmanExporter generates valid OBJ string', () {
    final skeleton = StickmanSkeleton();

    // Modify some properties to ensure they are reflected
    skeleton.headRadius = 5.0;
    skeleton.strokeWidth = 2.0;

    // Move hip to origin to check coordinates easily
    skeleton.hip = v.Vector3.zero();
    // Move neck to (0, 10, 0)
    skeleton.neck = v.Vector3(0, 10, 0);

    final obj = StickmanExporter.generateObjString(skeleton);

    // Basic structure check
    expect(obj, contains("# Stickman 3D OBJ Export"));
    expect(obj, contains("o Stickman"));
    expect(obj, contains("v ")); // Has vertices
    expect(obj, contains("f ")); // Has faces

    // Check for a vertex on the head cube
    // Head is typically at (0, -22, 0) relative to Neck (0, -14.7, 0) by default.
    // In this test, we didn't set head explicitly, so it uses default relative pos?
    // No, StickmanSkeleton initializes with absolute positions.
    // We set neck to (0,10,0). Head is not updated automatically by setter of neck unless we use Animator.
    // So Head is at default position (0, -22, 0)

    final headPos = skeleton.head!;
    final r = skeleton.headRadius;

    final checkX = headPos.x + r;
    final checkY = headPos.y + r;
    final checkZ = headPos.z + r;

    expect(obj, contains("v $checkX $checkY $checkZ"));
  });
}
