import 'dart:io';

import 'package:build/build.dart';
import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

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
        
        // Fetch dependencies for the downloaded protoc plugin packages.
        await _fetchDependencies(protocPluginPackageDirectory.path, packages);

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

/// Fetches dependencies for the downloaded protoc plugin packages.
///
/// This function iterates through all packages, separating them into standalone
/// and workspace-based packages. It runs `pub get` for standalone packages
/// individually. For workspace packages, it determines the most compatible SDK
/// constraint, generates a workspace `pubspec.yaml`, and runs `pub get` once.
Future<void> _fetchDependencies(
  String protocPluginPackageDirectory,
  List<String> packages,
) async {
  final standalonePackages = <String>[];
  final workspacePackages = <String>[];

  // For workspace packages, we'll try to find the sdk constrain
  VersionConstraint? workspaceSdkConstraint;
  String workspaceSdkVersionStr = '">=3.5.0"';

  for (final package in packages) {
    final pubspecFile = File(path.join(
      protocPluginPackageDirectory,
      package,
      'pubspec.yaml',
    ));

    if (!await pubspecFile.exists()) continue;

    final pubspecContent = await pubspecFile.readAsString();
    final pubspecYaml = loadYaml(pubspecContent) as YamlMap;

    if (pubspecYaml['resolution'] != 'workspace') {
      standalonePackages.add(package);
    } else {
      workspacePackages.add(package);
      final sdkConstraintStr = pubspecYaml['environment']?['sdk'] as String?;
      if (sdkConstraintStr != null) {
        final sdkConstraint = VersionConstraint.parse(sdkConstraintStr);
        if (workspaceSdkConstraint == null) {
          workspaceSdkConstraint = sdkConstraint;
        } else {
          final mergedConstraints = workspaceSdkConstraint.union(sdkConstraint);
          if (mergedConstraints.isEmpty) {
            log.warning(
                "Failed to merge SDK constraints for workspace packages, ignoring $sdkConstraintStr as it did not merge with $workspaceSdkVersionStr.");
          } else {
            workspaceSdkConstraint = mergedConstraints;
          }
        }

        workspaceSdkVersionStr = workspaceSdkConstraint.toString();
      }
    }
  }

  // Fetch dependencies for standalone packages individually.
  if (standalonePackages.isNotEmpty) {
    await Future.wait(
        standalonePackages.map((pkg) => ProcessExtensions.runSafely(
              'dart',
              ['pub', 'get'],
              workingDirectory: path.join(protocPluginPackageDirectory, pkg),
            )));
  }

  // If there are workspace packages, handle them together.
  if (workspacePackages.isNotEmpty) {
    // Create a temporary pubspec.yaml to define the workspace.
    final workspacePubspec = File(
      path.join(protocPluginPackageDirectory, 'pubspec.yaml'),
    );
    await workspacePubspec.writeAsString('''
name: _protoc_builder_workspace
publish_to: none
environment:
  sdk: '$workspaceSdkVersionStr'

workspace:
${workspacePackages.map((p) => '  - $p').join('\n')}
''');

    // Fetch dependencies for all packages in the workspace.
    await ProcessExtensions.runSafely(
      'dart',
      ['pub', 'get'],
      workingDirectory: protocPluginPackageDirectory,
    );
  }
}
