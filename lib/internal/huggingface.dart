import 'package:dio/dio.dart';

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
        }
      },
    );
    print("File downloaded to: $path");
  } catch (e) {
    print("Error downloading file: $e");
  }
}
