# stickman-animator

**stickman animator** — a small library and editor for creating stickman poses and animations in Dart/Flutter. 🎨

## Project files (*.sap) ✅

- Project files use the extension **`.sap`** (short for *Stickman Animator Project*).
- A `.sap` file is a JSON document that contains either:
  - A full project with a top-level `clips` list: `{ "version": 1, "clips": [ ... ] }` (the usual project export), or
  - A single-clip/keyframe export that includes `keyframes` (legacy/single-clip import support).
- The saved `.sap` file includes both animation data (clips/keyframes) and pose output data for the skeleton so another app can restore configured poses and animations.

## Usage 🔧

- Use `StickmanPersistence.saveProject(List<StickmanClip> clips)` to save your current project as a `.sap` file.
- Use `StickmanPersistence.loadProject()` to pick a `.sap` file and load its contained clips into your app. The function returns `List<StickmanClip>?` or `null` if no file was picked or a parse error occurred.

> Note: Files are plain JSON and are easy to include in other projects—an importing app can bundle a `.sap` file and call `StickmanPersistence.loadProject()` or parse the JSON and convert to `StickmanClip` objects using `StickmanClip.fromJson`.

## Example

- Default saved file name: `stickman_project_<timestamp>.sap` (created by the editor when choosing "Save Project").

## Integration with your Game/App

`StickmanPersistence` is designed for user-picked files (using file pickers), but games typically load assets directly from the bundle.

Use this helper function to load `.sap` files from your assets:

```dart
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:stickman_3d/stickman_3d.dart';

Future<List<StickmanClip>> loadStickmanAssets(String assetPath) async {
  final jsonString = await rootBundle.loadString(assetPath);
  final jsonMap = jsonDecode(jsonString);

  if (jsonMap is Map<String, dynamic> && jsonMap.containsKey('clips')) {
    return (jsonMap['clips'] as List).map((c) => StickmanClip.fromJson(c)).toList();
  } else {
    return [StickmanClip.fromJson(jsonMap)];
  }
}
```
