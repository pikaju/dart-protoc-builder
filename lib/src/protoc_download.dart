import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

Uri _protocUriFromVersion(String version) {
  String platformString;
  switch (Platform.operatingSystem) {
    case 'windows':
      platformString = 'win64';
      break;
    case 'macos':
      platformString = 'osx-x86_64';
      break;
    case 'linux':
      platformString = 'linux-x86_64';
      break;
    default:
      throw UnsupportedError('Build platform not supported.');
  }
  return Uri.parse(
      'https://github.com/protocolbuffers/protobuf/releases/download/v$version/protoc-$version-$platformString.zip');
}

String _protocExecutableName() {
  return Platform.isWindows ? 'protoc.exe' : 'protoc';
}

/// Downloads the Protobuf compiler from the GitHub Releases page and extracts
/// it to a temporary working directory.
/// Returns the path to the protoc executable that can be used by a [Process].
Future<String> downloadProtoc(String version) async {
  // Create a temporary directory for the proto compiler of the given version.
  final tempDirectory = path.join(
    '.dart_tool',
    'build',
    'protoc_builder',
    'compiler',
    'v${version.replaceAll('.', '_')}',
  );
  final protoc = path.join(tempDirectory, 'bin', _protocExecutableName());

  // If the compiler has already been downloaded, the function is done.
  if (await Directory(tempDirectory).exists()) return protoc;

  // Download and unzip the .zip file containing protoc and Google .proto files.
  final archive = ZipDecoder()
      .decodeBytes(await http.readBytes(_protocUriFromVersion(version)));
  for (final file in archive) {
    final filename = file.name;
    if (file.isFile) {
      final fileHandle = File(path.join(tempDirectory, filename));
      await fileHandle.create(recursive: true);
      await fileHandle.writeAsBytes(file.content as List<int>);
    }
  }

  // Make protoc executable on non-Windows platforms.
  if (!Platform.isWindows) {
    await Process.run('chmod', ['+x', protoc]);
  }

  return protoc;
}
