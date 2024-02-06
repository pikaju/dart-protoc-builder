import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'utility.dart';

/// A [Directory] to store all downloaded versions of the proto compiler.
final Directory _compilerDirectory =
    Directory(path.join(temporaryDirectory.path, 'compiler'));

Uri _protocUriFromVersion(String version) {
  String platformString;
  if (Platform.isWindows) {
    platformString = Abi.current() == Abi.windowsIA32 ? 'win32' : 'win64';
  } else if (Platform.isMacOS) {
    platformString =
      Abi.current() == Abi.macosArm64 ? 'osx-aarch_64' : 'osx-x86_64';
  } else if (Platform.isLinux) {
    platformString =
      Abi.current() == Abi.linuxArm64 ? 'linux-aarch_64' : 'linux-x86_64';
  } else {
    throw UnsupportedError('Build platform not supported.');
  }
  return Uri.parse(
      'https://github.com/protocolbuffers/protobuf/releases/download/v$version/protoc-$version-$platformString.zip');
}

String _protocExecutableName() {
  return Platform.isWindows ? 'protoc.exe' : 'protoc';
}

/// Guard to avoid multiple download of protoc compiler.
bool protocFetched = false;

/// Downloads the Protobuf compiler from the GitHub Releases page and extracts
/// it to a temporary working directory.
/// Returns the path to the protoc executable that can be used by a [Process].
Future<File> fetchProtoc(String version) async {
  // Create a temporary directory for the proto compiler of the given version.
  final versionDirectory = Directory(path.join(
    _compilerDirectory.path,
    'v${version.replaceAll('.', '_')}',
  ));
  final protoc = File(
    path.join(versionDirectory.path, 'bin', _protocExecutableName()),
  );
  if (protocFetched) {
    int retries = 0;
    // If the compiler version has already been downloaded, the function is done.
    while (!await protoc.exists() && retries < 10) {
      await Future.delayed(Duration(milliseconds: 100));
      retries++;
    }
    return protoc;
  }
  protocFetched = true;

  // Download and unzip the .zip file containing protoc and Google .proto files.
  await unzipUri(_protocUriFromVersion(version), versionDirectory);

  // Make protoc executable on non-Windows platforms.
  await addRunnableFlag(protoc);

  return protoc;
}
