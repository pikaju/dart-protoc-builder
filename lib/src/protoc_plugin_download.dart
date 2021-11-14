import 'dart:io';

import 'package:path/path.dart' as path;

import 'utility.dart';

/// A [Directory] to store all downloaded versions of the protoc Dart plugin.
final Directory _pluginDirectory =
    Directory(path.join(temporaryDirectory.path, 'plugin'));

Uri _protocPluginUriFromVersion(String? version) {
  return Uri.parse(
      'https://github.com/google/protobuf.dart/archive/refs/tags/protoc_plugin-v$version.zip');
}

String _protoPluginName() {
  return Platform.isWindows ? 'protoc-gen-dart.bat' : 'protoc-gen-dart';
}

/// Downloads the Dart plugin for the Protobuf compiler from the GitHub Releases
/// page and extracts it to a temporary working directory.
/// Returns the path to the binaries directory that should be added to the PATH
/// environment variable for protoc to use.
Future<File> fetchProtocPlugin(String version) async {
  // Create a temporary directory for the proto plugin of the given version.
  final versionDirectory = Directory(
      path.join(_pluginDirectory.path, 'v${version.replaceAll('.', '_')}'));
  final protocPluginPackageDirectory = Directory(path.join(
    versionDirectory.path,
    'protobuf.dart-protoc_plugin-v$version',
    'protoc_plugin',
  ));
  final protocPlugin = File(
    path.join(protocPluginPackageDirectory.path, 'bin', _protoPluginName()),
  );

  // If the plugin has already been downloaded, the function is done.
  if (await versionDirectory.exists()) return protocPlugin;

  // Download and unzip the .zip file containing protoc and Google .proto files.
  await unzipUri(
    _protocPluginUriFromVersion(version),
    versionDirectory,
    // Only extract the protoc_plugin from the Protobuf Git repository.
    (file) => path.split(file.name).contains('protoc_plugin'),
  );

  // Fetch protoc_plugin package dependencies.
  await ProcessExtensions.runSafely('dart', ['pub', 'get'],
      workingDirectory: protocPluginPackageDirectory.path);

  // Make plugin executable on non-Windows platforms.
  await addRunnableFlag(protocPlugin);

  return protocPlugin;
}
