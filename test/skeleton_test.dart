import 'package:flutter_test/flutter_test.dart';
import 'package:stickman_3d/stickman_3d.dart';
import 'package:vector_math/vector_math_64.dart' as v;

void main() {
  test('StickmanSkeleton initializes with standing pose', () {
    final skeleton = StickmanSkeleton();

    // Hip at origin
    expect(skeleton.hip, equals(v.Vector3(0, 0, 0)));

    // Feet on ground (y=25)
    expect(skeleton.lFoot.y, equals(25));
    expect(skeleton.rFoot.y, equals(25));

    // Head above origin
    expect(skeleton.head!.y, lessThan(0));
    expect(skeleton.neck.y, lessThan(0));

    // Shoulders
    expect(skeleton.lShoulder.x, lessThan(0));
    expect(skeleton.rShoulder.x, greaterThan(0));

    // Hands lower than shoulders in standing pose (y is down)
    // lShoulder y = -15, lHand y = 0. 0 > -15.
    expect(skeleton.lHand.y, greaterThan(skeleton.lShoulder.y));
    expect(skeleton.rHand.y, greaterThan(skeleton.rShoulder.y));
  });
}
