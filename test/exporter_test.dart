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

    // Check specific logic
    // We expect vertices for the box connecting Hip and Neck
    // Box length = 10. Thickness = 2.0. Half thickness = 1.0.
    // Start (0,0,0), End (0,10,0). Direction (0,1,0). Up (0,0,1).
    // Right = (0,1,0) x (0,0,1) = (1,0,0).
    // FinalUp = (1,0,0) x (0,1,0) = (0,0,1).
    // Offsets are +/- 1.0 along X and Z.
    // e.g. Point 1: Start + Right(1) + FinalUp(1) => (1, 0, 1)

    // Check if we can find at least one expected vertex from the hip-neck bone
    // Note: Due to floating point formatting, we might need flexible matching,
    // but Vector3.toString() usually produces standard format.
    // The exporter uses string interpolation "${p.x} ${p.y} ${p.z}"

    // Let's check for "v 1.0 0.0 1.0" or similar.
    // Actually exact matching might be tricky due to potential float variations.
    // But since inputs are integers/simple floats, it might be clean.

    // Let's count vertices roughly.
    // Head: Cube = 8 vertices.
    // Bones:
    // Hip has children: Neck, Left Hip, Right Hip.
    // Neck has children: Head, L Shoulder, R Shoulder.
    // ...
    // There are many bones.

    // Just verify the head cube exists.
    // Head position is skeleton.head!.
    final headPos = skeleton.head!;
    final r = skeleton.headRadius;

    // Check for a vertex on the head cube
    // e.g. headPos.x + r
    final checkX = headPos.x + r;
    final checkY = headPos.y + r;
    final checkZ = headPos.z + r;

    expect(obj, contains("v $checkX $checkY $checkZ"));
  });
}
