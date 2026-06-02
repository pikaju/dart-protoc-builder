import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:build/build.dart';
import 'package:path/path.dart' as path;
import 'package:protoc_builder/src/protoc_plugin_download.dart';
import 'package:protoc_builder/src/utility.dart';
import 'package:yaml/yaml.dart';

import 'protoc_download.dart';

/// Adds a forward slash between the two paths.
///
/// NOTE: Do NOT use path.join, since package:build is expecting a forward slash
/// regardless of the platform, but path.join will return a backslash on Windows.
String join(String a, String b) => a.endsWith("/") ? "$a$b" : "$a/$b";

class ProtocBuilder implements Builder {
  static const defaultProtocVersion = '27.0';
  static const defaultProtocPluginVersion = '21.1.2';
  static const defaultRootDirectory = 'proto/';
  static const defaultProtoPaths = ['proto/'];
  static const defaultOutputDirectory = 'lib/src/proto/';
  static const defaultGrpcEnabled = false;
  static const defaultUseInstalledProtoc = false;
  static const defaultPrecompileProtocPlugin = true;

  ProtocBuilder(this.options)
      : protobufVersion = options.config['protobuf_version'] as String? ??
            defaultProtocVersion,
        protocPluginVersion =
            options.config['protoc_plugin_version'] as String? ??
                defaultProtocPluginVersion,
        rootDirectory =
            options.config['root_dir'] as String? ?? defaultRootDirectory,
        protoPaths = (options.config['proto_paths'] as YamlList?)
                ?.nodes
                .map((e) => e.value as String)
                .toList() ??
            defaultProtoPaths,
        outputDirectory = path.normalize(
            options.config['out_dir'] as String? ?? defaultOutputDirectory),
        grpcEnabled = options.config['grpc'] as bool? ?? defaultGrpcEnabled,
        useInstalledProtoc = options.config['use_installed_protoc'] as bool? ??
            defaultUseInstalledProtoc,
        precompileProtocPlugin =
            options.config['precompile_protoc_plugin'] as bool? ??
                defaultPrecompileProtocPlugin;

  final BuilderOptions options;

  final String protobufVersion;
  final String protocPluginVersion;
  final String rootDirectory;
  final List<String> protoPaths;
  final String outputDirectory;
  final bool grpcEnabled;
  final bool useInstalledProtoc;
  final bool precompileProtocPlugin;

  @override
  Future<void> build(BuildStep buildStep) async {
    // When "useInstalledProtoc", we will not fetch any external resources
    // (protoc resolved via PATH, so keep the bare name).
    //
    // Otherwise the downloaded binaries live under the build root's
    // `.dart_tool/build/protoc_builder`, but protoc is spawned with
    // `workingDirectory: packageRoot` (a package subdir under --workspace).
    // Resolve to absolute paths so the relative download location is not
    // re-resolved against the package root.
    final protoc = useInstalledProtoc
        ? File('protoc')
        : (await fetchProtoc(protobufVersion)).absolute;
    final protocPlugin = useInstalledProtoc
        ? File('')
        : (await fetchProtocPlugin(protocPluginVersion, precompileProtocPlugin))
            .absolute;

    final inputPath = path.normalize(buildStep.inputId.path);

    final pluginParameters = grpcEnabled ? 'grpc:' : '';

    // Resolve the package root directory. We look up the package root from the Dart
    // package config and run protoc from there.
    final packageRoot =
        await _resolvePackageRoot(buildStep.inputId.package);

    // Read the input path to signal to the build graph that if the file changes
    // then it should be rebuilt.
    await buildStep.readAsString(buildStep.inputId);
    // Create the output directory (if necessary)
    await Directory(path.join(packageRoot, outputDirectory))
        .create(recursive: true);
    // And run the "protoc" process
    await ProcessExtensions.runSafely(
      protoc.path,
      collectProtocArguments(protocPlugin, pluginParameters, inputPath),
      workingDirectory: packageRoot,
    );

    // Just as with the read, the build runner spies on what we write, so we
    // need to write each output file explicitly, even though they've already
    // been written by protoc. This will ensure that if an output file is
    // deleted, a future build will recreate it. This also checks that the files
    // we were expected to write were actually written, since this will fail if
    // an output file wasn't created by protoc.
    await Future.wait(buildStep.allowedOutputs.map((AssetId out) async {
      var file = loadOutputFile(out, packageRoot);
      // When there is no service definition in a .proto file, the respective
      // .pbgrpc.dart file is not generated. So, we will tolerate its absence.
      if (file.path.endsWith('.pbgrpc.dart') && !await file.exists()) {
        return;
      }
      await buildStep.writeAsBytes(out, file.readAsBytes());
    }));
  }

  /// Load the output file.
  /// This method has been explicitly extracted so it can be easily overridden
  /// in unit tests, where we may need to exert some extra control.
   File loadOutputFile(AssetId out, String packageRoot) =>
      File(path.join(packageRoot, out.path));

  /// Resolves the filesystem root directory for [packageName] by reading
  /// `.dart_tool/package_config.json`. Falls back to `Directory.current` when
  /// the config is absent or the package is not listed (e.g. the root package).
  Future<String> _resolvePackageRoot(String packageName) async {
    final configFile = File(
        path.join('.dart_tool', 'package_config.json'));
    if (!await configFile.exists()) return Directory.current.path;

    final config =
        json.decode(await configFile.readAsString()) as Map<String, dynamic>;
    final packages = config['packages'] as List<dynamic>;
    for (final pkg in packages) {
      if ((pkg as Map<String, dynamic>)['name'] == packageName) {
        final rootUri = pkg['rootUri'] as String;
        if (rootUri.startsWith('file://')) {
          return Uri.parse(rootUri).toFilePath();
        }
        // rootUri is relative to the .dart_tool directory
        return path.normalize(
            path.join(path.dirname(configFile.path), rootUri));
      }
    }
    return Directory.current.path;
  }

  /// Collect all arguments to be added to the "protoc" call.
  /// This method has been explicitly extracted so it can be easily overridden
  /// in unit tests, where we may need to exert some extra control.
  List<String> collectProtocArguments(
      File protocPlugin, String pluginParameters, String inputPath) {
    return <String>[
      if (protocPlugin.path.isNotEmpty)
        '--plugin=protoc-gen-dart=${protocPlugin.path}',
      '--dart_out=$pluginParameters${path.join('.', outputDirectory)}',
      ...protoPaths
          .map((protoPath) => '--proto_path=${path.join('.', protoPath)}'),
      path.join('.', inputPath),
    ];
  }

  @override
  Map<String, List<String>> get buildExtensions {
    return {
      join(rootDirectory, '{{}}.proto'): [
        '$outputDirectory/{{}}.pb.dart',
        '$outputDirectory/{{}}.pbenum.dart',
        '$outputDirectory/{{}}.pbjson.dart',
        if (!grpcEnabled) '$outputDirectory/{{}}.pbserver.dart',
        if (grpcEnabled) '$outputDirectory/{{}}.pbgrpc.dart',
      ],
    };
  }
}
