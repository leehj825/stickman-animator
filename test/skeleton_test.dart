import 'package:flutter_test/flutter_test.dart';
import 'package:stickman_3d/stickman_3d.dart';
import 'package:vector_math/vector_math_64.dart' as v;

void main() {
  test('StickmanSkeleton initializes with user defined standing pose', () {
    final skeleton = StickmanSkeleton();

    // Check specific coordinates from the requested update
    expect(skeleton.hip.x, closeTo(1.0, 0.001));
    expect(skeleton.neck.y, closeTo(-14.7, 0.001));

    // Check hierarchy: Arms connected to neck
    expect(skeleton.nodes['neck']!.children.any((c) => c.id == 'lElbow'), isTrue);
    expect(skeleton.nodes['neck']!.children.any((c) => c.id == 'rElbow'), isTrue);

    // Check hierarchy: Legs connected to hip
    expect(skeleton.nodes['hip']!.children.any((c) => c.id == 'lKnee'), isTrue);
    expect(skeleton.nodes['hip']!.children.any((c) => c.id == 'rKnee'), isTrue);

    // Check stroke width update
    expect(skeleton.strokeWidth, closeTo(4.6, 0.001));
  });
}
