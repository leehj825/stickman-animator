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

---

If you'd like, I can also add a short example snippet showing how to include a `.sap` file in another Flutter app and programmatically load it. 💡
