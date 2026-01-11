import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'stickman_animation.dart';

class StickmanPersistence {

  /// Saves the clip to a JSON file and prompts user to save/share it.
  static Future<void> saveClip(StickmanClip clip) async {
    try {
      final jsonString = jsonEncode(clip.toJson());

      // Use a sanitized name for the file
      final safeName = clip.name.replaceAll(RegExp(r'[^\w\s]+'), '').trim().replaceAll(' ', '_');

      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Project',
        fileName: '$safeName.stickman',
        type: FileType.any,
      );

      if (outputFile != null) {
        final file = File(outputFile);
        await file.writeAsString(jsonString);
      }

    } catch (e) {
      print('Error saving clip: $e');
      throw e;
    }
  }

  /// Opens a file picker to load a .stickman or .json file.
  static Future<StickmanClip?> loadClip() async {
    try {
      // Use FileType.any to avoid grayed out files on Google Drive/Android
      // due to unrecognized custom extensions/MIME types.
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true, // Ensure bytes are loaded if path is not available
      );

      if (result != null) {
        String content;

        if (result.files.single.bytes != null) {
          // Web or restricted access where bytes are provided directly
          content = utf8.decode(result.files.single.bytes!);
        } else if (result.files.single.path != null) {
          // Mobile/Desktop with file path access
          File file = File(result.files.single.path!);
          content = await file.readAsString();
        } else {
          print('Error: No file path or bytes available.');
          return null;
        }

        Map<String, dynamic> jsonMap = jsonDecode(content);
        return StickmanClip.fromJson(jsonMap);
      } else {
        // User canceled
        return null;
      }
    } catch (e) {
      print('Error loading clip: $e');
      // In a real app we might want to return an error result or throw
      return null;
    }
  }
}
