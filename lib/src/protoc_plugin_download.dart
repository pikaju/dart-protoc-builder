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

class RunOnceProcess {
  bool onTheRun = false;
  bool done = false;

  ///
  /// Wrap a process to [execute] once per all build steps and ensure, that it is executed once
  /// only.
  ///
  Future<void> executeOnce(Future<bool> Function() execute) async {
    if (done) {
      // print("Protoc compiler had been unpacked already.");
      return;
    }
    while (onTheRun) {
      // print("waiting for other process unpacking protoc compiler");
      await Future.delayed(const Duration(seconds: 1));
    }
    if (!done) {
      //print("Need to unpack the protoc compiler");
      onTheRun = true;
      try {
        done = await execute();
        //print("Protoc compiler was unpacked with success=$_unpacked");
      } finally {
        onTheRun = false;
      }
    }
  }

}

RunOnceProcess _unpack = RunOnceProcess();
RunOnceProcess _precompile = RunOnceProcess();

/// Downloads the Dart plugin for the Protobuf compiler from the GitHub Releases
/// page and extracts it to a temporary working directory.
/// Returns the path to the binaries directory that should be added to the PATH
/// environment variable for protoc to use.
Future<File> fetchProtocPlugin(
    String version, bool precompileProtocPlugin) async {
  final packages = const ['protoc_plugin', 'protobuf'];
  // Create a temporary directory for the proto plugin of the given version.
  final versionDirectory = Directory(
      path.join(_pluginDirectory.path, 'v${version.replaceAll('.', '_')}'));
  final protocPluginPackageDirectory = Directory(path.join(
    versionDirectory.path,
    'protobuf.dart-protoc_plugin-v$version',
  ));

  final protocPluginDirectory = Directory(
    path.join(
      protocPluginPackageDirectory.path,
      'protoc_plugin',
    ),
  );

  final protocPlugin = File(
    path.join(
      protocPluginDirectory.path,
      'bin',
      _protoPluginName(),
    ),
  );

  await _unpack.executeOnce(() async {
    try {
      // If the plugin has not been downloaded yet, download it.
      if (!await versionDirectory.exists()) {
        // Download and unzip the .zip file containing protoc and Google .proto files.
        await unzipUri(
          _protocPluginUriFromVersion(version),
          versionDirectory,
          // Only extract the protoc_plugin from the Protobuf Git repository.
              (file) => packages.contains(path.split(file.name)[1]),
        );

        // Fetch protoc_plugin package dependencies.
        await Future.wait(packages.map((pkg) =>
            ProcessExtensions.runSafely(
              'dart',
              ['pub', 'get'],
              workingDirectory: path.join(
                  protocPluginPackageDirectory.path, pkg),
            )));

        // Make plugin executable on non-Windows platforms.
        await addRunnableFlag(protocPlugin);
      }
      return true;
    } catch(ex) {
      print("Failed to unpack protoc plugin with $ex.");
      return false;
    }
  });

  if (precompileProtocPlugin) {
    final precompiledName = "precompiled.exe";
    final precompiledProtocPlugin = File(
      path.join(
        protocPluginDirectory.path,
        precompiledName,
      ),
    );
    await _precompile.executeOnce(() async {
      if (!await precompiledProtocPlugin.exists()) {
        // Compile the entry point file.
        await ProcessExtensions.runSafely(
          'dart',
          [
            'compile',
            'exe',
            'bin/protoc_plugin.dart',
            '-o',
            precompiledName,
          ],
          workingDirectory: protocPluginDirectory.path,
        );
        // Make sure the executable is runnable on non-Windows platforms.
        await addRunnableFlag(precompiledProtocPlugin);
      }
      return true;
    });
    return precompiledProtocPlugin;
  } else {
    return protocPlugin;
  }
}
