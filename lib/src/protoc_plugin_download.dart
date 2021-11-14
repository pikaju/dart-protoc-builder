import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

Uri _protocPluginUriFromVersion(String? version) {
  return Uri.parse(
      'https://github.com/google/protobuf.dart/archive/refs/tags/protoc_plugin-v$version.zip');
}

/// Downloads the Dart plugin for the Protobuf compiler from the GitHub Releases
/// page and extracts it to a temporary working directory.
/// Returns the path to the binaries directory that should be added to the PATH
/// environment variable for protoc to use.
Future<String> downloadProtocPlugin(String version) async {
  // Create a temporary directory for the proto plugin of the given version.
  final tempDirectory = path.join(
    '.dart_tool',
    'build',
    'protoc_builder',
    'plugin',
    'v${version.replaceAll('.', '_')}',
  );
  final binDirectory = path.join(
    tempDirectory,
    'protobuf.dart-protoc_plugin-v$version',
    'protoc_plugin',
    'bin',
  );

  // If the plugin has already been downloaded, the function is done.
  if (await Directory(tempDirectory).exists()) return binDirectory;

  // Download and unzip the .zip file containing protoc and Google .proto files.
  final archive = ZipDecoder()
      .decodeBytes(await http.readBytes(_protocPluginUriFromVersion(version)));
  for (final file in archive) {
    final filename = file.name;
    if (file.isFile) {
      final fileHandle = File(path.join(tempDirectory, filename));
      await fileHandle.create(recursive: true);
      await fileHandle.writeAsBytes(file.content as List<int>);
    }
  }

  // Make plugin executable on non-Windows platforms.
  if (!Platform.isWindows) {
    await Process.run(
        'chmod', ['+x', path.join(binDirectory, 'protoc-gen-dart')]);
  }

  return binDirectory;
}
