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
      final safeName = clip.name.replaceAll(RegExp(r'[^\w\s]+'), '').trim().replaceAll(' ', '_');

      if (Platform.isAndroid || Platform.isIOS) {
        // Mobile: Use Share Sheet
        final directory = await getTemporaryDirectory();
        final file = File('${directory.path}/$safeName.stickman');
        await file.writeAsString(jsonString);
        await Share.shareXFiles([XFile(file.path)], text: 'Stickman Project');
      } else {
        // Desktop: Use Save File Dialog
        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Project',
          fileName: '$safeName.stickman',
          type: FileType.any,
        );

        if (outputFile != null) {
          final file = File(outputFile);
          await file.writeAsString(jsonString);
        }
      }
    } catch (e) {
      print('Error saving clip: $e');
      throw e;
    }
  }

  /// Opens a file picker to load a .stickman or .json file.
  static Future<StickmanClip?> loadClip() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );

      if (result != null) {
        String content;
        if (result.files.single.bytes != null) {
          content = utf8.decode(result.files.single.bytes!);
        } else if (result.files.single.path != null) {
          File file = File(result.files.single.path!);
          content = await file.readAsString();
        } else {
          return null;
        }
        Map<String, dynamic> jsonMap = jsonDecode(content);
        return StickmanClip.fromJson(jsonMap);
      }
      return null;
    } catch (e) {
      print('Error loading clip: $e');
      return null;
    }
  }
}
