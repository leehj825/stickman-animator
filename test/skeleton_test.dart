import 'package:flutter_test/flutter_test.dart';
import 'package:stickman_3d/stickman_3d.dart';
import 'package:vector_math/vector_math_64.dart' as v;

void main() {
  test('StickmanSkeleton initializes with user defined standing pose', () {
    final skeleton = StickmanSkeleton();

    // Check specific coordinates from the requested update
    expect(skeleton.hip.x, closeTo(1.0, 0.001));
    expect(skeleton.neck.y, closeTo(-14.7, 0.001));

    // Check narrow shoulders (user requested "remove hip and shoulder points" effect)
    // lShoulder (-0.6) is very close to neck (0.0)
    expect(skeleton.lShoulder.x, closeTo(-0.6, 0.001));
    expect(skeleton.rShoulder.x, closeTo(-0.2, 0.001));

    // Check narrow hips
    expect(skeleton.lHip.x, closeTo(0.6, 0.001));
    expect(skeleton.rHip.x, closeTo(0.6, 0.001));

    // Check stroke width update
    expect(skeleton.strokeWidth, closeTo(4.6, 0.001));
  });
}
