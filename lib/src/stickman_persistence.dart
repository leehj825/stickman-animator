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

      // Get temporary directory
      final directory = await getTemporaryDirectory();
      // Use a sanitized name for the file
      final safeName = clip.name.replaceAll(RegExp(r'[^\w\s]+'), '').trim().replaceAll(' ', '_');
      final file = File('${directory.path}/$safeName.stickman');

      await file.writeAsString(jsonString);

      // Use share_plus to export the file (works on Android/iOS/Desktop)
      // On desktop this usually opens a save dialog or shares to mail etc.
      await Share.shareXFiles([XFile(file.path)], text: 'Stickman Animation Project');

    } catch (e) {
      print('Error saving clip: $e');
      throw e;
    }
  }

  /// Opens a file picker to load a .stickman or .json file.
  static Future<StickmanClip?> loadClip() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['stickman', 'json'],
      );

      if (result != null && result.files.single.path != null) {
        File file = File(result.files.single.path!);
        String content = await file.readAsString();
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
