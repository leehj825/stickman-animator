import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'stickman_animation.dart';

class StickmanProjectData {
  final List<StickmanClip> clips;
  final double headRadius;
  final double strokeWidth;

  StickmanProjectData({
    required this.clips,
    required this.headRadius,
    required this.strokeWidth,
  });
}

class StickmanPersistence {

  /// Saves the ENTIRE PROJECT (List of clips + Global Style) to a single JSON file (extension: .sap).
  static Future<void> saveProject(List<StickmanClip> clips, double headRadius, double strokeWidth) async {
    try {
      final projectMap = {
        'version': 1,
        'headRadius': headRadius,
        'strokeWidth': strokeWidth,
        'clips': clips.map((c) => c.toJson()).toList(),
      };

      final jsonString = jsonEncode(projectMap);
      final fileName = 'stickman_project_${DateTime.now().millisecondsSinceEpoch}.sap';

      if (Platform.isAndroid || Platform.isIOS) {
        final directory = await getTemporaryDirectory();
        final file = File('${directory.path}/$fileName');
        await file.writeAsString(jsonString);
        await Share.shareXFiles([XFile(file.path)], text: 'Stickman Project (.sap) (All Animations)');
      } else {
        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Project',
          fileName: fileName,
          type: FileType.any,
        );
        if (outputFile != null) {
          final file = File(outputFile);
          await file.writeAsString(jsonString);
        }
      }
    } catch (e) {
      print('Error saving project: $e');
      throw e;
    }
  }

  /// Loads a project file and returns the Project Data.
  static Future<StickmanProjectData?> loadProject() async {
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
        List<StickmanClip> clips = [];

        if (jsonMap.containsKey('clips')) {
           clips = (jsonMap['clips'] as List)
              .map((c) => StickmanClip.fromJson(c))
              .toList();
        }
        else if (jsonMap.containsKey('keyframes')) {
          // Legacy single-clip file support
           clips = [StickmanClip.fromJson(jsonMap)];
        }

        // Load style if present, otherwise default to standard values
        double headRadius = (jsonMap['headRadius'] as num?)?.toDouble() ?? 6.0;
        double strokeWidth = (jsonMap['strokeWidth'] as num?)?.toDouble() ?? 4.6;

        return StickmanProjectData(
          clips: clips,
          headRadius: headRadius,
          strokeWidth: strokeWidth
        );
      }
      return null;
    } catch (e) {
      print('Error loading project: $e');
      return null;
    }
  }
}
