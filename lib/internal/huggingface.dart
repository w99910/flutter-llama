import 'package:dio/dio.dart';

/// Model information from Hugging Face API
class HFModelFile {
  final String path;
  final int size;
  final String type;

  HFModelFile({required this.path, required this.size, required this.type});

  factory HFModelFile.fromJson(Map<String, dynamic> json) {
    return HFModelFile(
      path: json['path'] as String,
      size: json['size'] as int,
      type: json['type'] as String,
    );
  }
}

String getHuggingFaceUrl({
  required String repoId,
  required String filename,
  String? revision,
  String? subfolder,
}) {
  // Default values
  const String defaultEndpoint = 'https://huggingface.co';
  const String defaultRevision = 'main';

  // Ensure the revision and subfolder are not null and are URI encoded
  final String encodedRevision = Uri.encodeComponent(
    revision ?? defaultRevision,
  );
  final String encodedFilename = Uri.encodeComponent(filename);
  final String? encodedSubfolder = subfolder != null
      ? Uri.encodeComponent(subfolder)
      : null;

  // Handle subfolder if provided
  final String fullPath = encodedSubfolder != null
      ? '$encodedSubfolder/$encodedFilename'
      : encodedFilename;

  // Construct the URL
  final String url =
      '$defaultEndpoint/$repoId/resolve/$encodedRevision/$fullPath';

  return url;
}

Future<void> downloadGGUF({
  required String repoId,
  required String filename,
  required String path,
  String? revision,
  String? subfolder,
  void Function(int received, int total)? onProgress,
}) async {
  final dio = Dio();
  final url = getHuggingFaceUrl(
    repoId: repoId,
    filename: filename,
    revision: revision,
    subfolder: subfolder,
  );
  try {
    await dio.download(
      url,
      path,
      onReceiveProgress: (received, total) {
        if (total != -1) {
          print((received / total * 100).toStringAsFixed(0) + "%");
          onProgress?.call(received, total);
        }
      },
    );
    print("File downloaded to: $path");
  } catch (e) {
    print("Error downloading file: $e");
    rethrow;
  }
}

/// List all files in a Hugging Face repository
Future<List<HFModelFile>> listRepoFiles({
  required String repoId,
  String? revision,
}) async {
  final dio = Dio();
  final encodedRevision = Uri.encodeComponent(revision ?? 'main');
  final url = 'https://huggingface.co/api/models/$repoId/tree/$encodedRevision';

  try {
    final response = await dio.get(url);
    if (response.statusCode == 200) {
      final List<dynamic> files = response.data as List<dynamic>;
      return files
          .map((file) => HFModelFile.fromJson(file as Map<String, dynamic>))
          .toList();
    } else {
      print("Failed to list repo files: ${response.statusCode}");
      return [];
    }
  } catch (e) {
    print("Error listing repo files: $e");
    return [];
  }
}

/// Find mmproj file for a given model filename
/// Looks for files with "mmproj" keyword and "f16" or "F16" quantization
String? findMmprojFile(List<HFModelFile> files, String modelFilename) {
  // Extract base model name without quantization
  // e.g., "SmolVLM-Instruct-Q4_K_M.gguf" -> "SmolVLM-Instruct"
  String baseName = modelFilename
      .replaceAll(RegExp(r'-Q\d+_[KML_]+.*\.gguf', caseSensitive: false), '')
      .replaceAll(RegExp(r'-IQ\d+_[XS]+.*\.gguf', caseSensitive: false), '')
      .replaceAll('.gguf', '');

  // Search for mmproj files matching the model
  for (var file in files) {
    final filename = file.path.toLowerCase();

    // Must contain "mmproj" keyword
    if (!filename.contains('mmproj')) continue;

    // Must be a .gguf file
    if (!filename.endsWith('.gguf')) continue;

    // Prefer f16 quantization
    if (filename.contains('f16') || filename.contains('F16')) {
      // Check if it matches the base model name
      if (filename.contains(baseName.toLowerCase())) {
        print("Found mmproj file with f16: ${file.path}");
        return file.path;
      }
    }
  }

  // Fallback: find any mmproj file for this model
  for (var file in files) {
    final filename = file.path.toLowerCase();
    if (filename.contains('mmproj') &&
        filename.endsWith('.gguf') &&
        filename.contains(baseName.toLowerCase())) {
      print("Found mmproj file (fallback): ${file.path}");
      return file.path;
    }
  }

  // Fallback 2: find any generic mmproj file (e.g., "mmproj-model-f16.gguf" for Gemma 3)
  for (var file in files) {
    final filename = file.path.toLowerCase();
    if (filename.contains('mmproj') && filename.endsWith('.gguf')) {
      print("Found generic mmproj file: ${file.path}");
      return file.path;
    }
  }

  print("No mmproj file found for model: $modelFilename");
  return null;
}

/// Download model with automatic mmproj detection and download
/// Returns a map with 'modelPath' and optional 'mmprojPath'
Future<Map<String, String?>> downloadModelWithMmproj({
  required String repoId,
  required String filename,
  required String savePath,
  String? revision,
  String? subfolder,
  bool autoDownloadMmproj = true,
  String? mmprojFilename, // User-specified mmproj filename
  void Function(String status, double progress)? onProgress,
}) async {
  final Map<String, String?> result = {'modelPath': null, 'mmprojPath': null};

  // Download the main model
  onProgress?.call('Downloading model: $filename', 0.0);
  await downloadGGUF(
    repoId: repoId,
    filename: filename,
    path: savePath,
    revision: revision,
    subfolder: subfolder,
    onProgress: (received, total) {
      final progress = received / total;
      onProgress?.call(
        'Downloading model: ${(progress * 100).toStringAsFixed(1)}%',
        progress * 0.7, // Model takes 70% of total progress
      );
    },
  );
  result['modelPath'] = savePath;

  // If autoDownloadMmproj is enabled, search for and download mmproj
  if (autoDownloadMmproj) {
    onProgress?.call('Searching for multimodal projector...', 0.7);
    print("Searching for mmproj file in repository...");

    String? mmprojFilenameToDownload;

    // Use user-specified mmproj filename if provided
    if (mmprojFilename != null && mmprojFilename.isNotEmpty) {
      print("Using user-specified mmproj filename: $mmprojFilename");
      mmprojFilenameToDownload = mmprojFilename;
    } else {
      // Auto-detect mmproj file
      final files = await listRepoFiles(repoId: repoId, revision: revision);
      mmprojFilenameToDownload = findMmprojFile(files, filename);
    }

    if (mmprojFilenameToDownload != null) {
      // Construct mmproj save path
      final mmprojPath = savePath.replaceAll(
        filename,
        mmprojFilenameToDownload
            .split('/')
            .last, // Get filename without subfolder
      );

      onProgress?.call('Downloading mmproj: $mmprojFilenameToDownload', 0.7);
      print("Downloading mmproj file: $mmprojFilenameToDownload");
      await downloadGGUF(
        repoId: repoId,
        filename: mmprojFilenameToDownload,
        path: mmprojPath,
        revision: revision,
        subfolder: subfolder,
        onProgress: (received, total) {
          final progress = received / total;
          onProgress?.call(
            'Downloading mmproj: ${(progress * 100).toStringAsFixed(1)}%',
            0.7 + (progress * 0.3), // mmproj takes remaining 30%
          );
        },
      );
      result['mmprojPath'] = mmprojPath;
      onProgress?.call('✓ Downloads complete!', 1.0);
      print("Mmproj downloaded successfully");
    } else {
      onProgress?.call('✓ Model downloaded (text-only, no vision)', 1.0);
      print("No mmproj file found - this model may not support vision/audio");
    }
  } else {
    onProgress?.call('✓ Model downloaded', 1.0);
  }

  return result;
}
