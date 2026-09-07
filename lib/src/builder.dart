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
  static const defaultProtocVersion = '36.1';
  static const defaultProtocPluginVersion = '25.0.0';
  static const defaultRootDirectory = 'proto/';
  static const defaultProtoPaths = ['proto/'];
  static const defaultOutputDirectory = 'lib/src/proto/';
  static const defaultGrpcEnabled = false;
  static const defaultUseInstalledProtoc = false;
  static const defaultPrecompileProtocPlugin = true;
  static const defaultProtocPluginParameters = <String>[];

  /// Output files that protoc_plugin only generates when there is something to
  /// put in them: .pbgrpc.dart requires a service definition, and newer plugin
  /// versions (22.3.0 and later) no longer write empty .pbserver.dart files
  /// (some versions also skipped empty .pbenum.dart files).
  static const optionalOutputExtensions = [
    '.pbgrpc.dart',
    '.pbserver.dart',
    '.pbenum.dart',
  ];

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
                defaultPrecompileProtocPlugin,
        protocPluginParameters =
            (options.config['protoc_plugin_parameters'] as List?)
                    ?.cast<String>() ??
                defaultProtocPluginParameters;

  final BuilderOptions options;

  final String protobufVersion;
  final String protocPluginVersion;
  final String rootDirectory;
  final List<String> protoPaths;
  final String outputDirectory;
  final bool grpcEnabled;
  final bool useInstalledProtoc;
  final bool precompileProtocPlugin;
  final List<String> protocPluginParameters;

  @override
  Future<void> build(BuildStep buildStep) async {
    // When "useInstalledProtoc", we will not fetch any external resources.
    // Downloaded binaries are resolved to absolute paths, since protoc is run
    // from the package root, which is not necessarily the current directory.
    final protoc = useInstalledProtoc
        ? File('protoc')
        : (await fetchProtoc(protobufVersion)).absolute;
    final protocPlugin = useInstalledProtoc
        ? File('')
        : (await fetchProtocPlugin(protocPluginVersion, precompileProtocPlugin))
            .absolute;

    // All paths handed to protoc are relative to the package being built. In
    // a regular build this is the current directory, but in a pub workspace
    // build (`build_runner build --workspace`) it is one of the workspace
    // members, so protoc is run from the resolved package root instead.
    final packageRoot = await resolvePackageRoot(buildStep.inputId.package);

    final inputPath = path.normalize(buildStep.inputId.path);

    var pluginParameters = {
      if (grpcEnabled) 'grpc',
      ...protocPluginParameters,
    }.join(',');
    if (pluginParameters.isNotEmpty) {
      pluginParameters = '$pluginParameters:';
    }

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
      // Some outputs are only generated when the .proto file contains the
      // respective definitions, so we tolerate their absence.
      if (optionalOutputExtensions.any(file.path.endsWith) &&
          !await file.exists()) {
        return;
      }
      await buildStep.writeAsBytes(out, file.readAsBytes());
    }));
  }

  /// Load the output file, which protoc has written relative to [packageRoot].
  /// This method has been explicitly extracted so it can be easily overridden
  /// in unit tests, where we may need to exert some extra control.
  File loadOutputFile(AssetId out, String packageRoot) =>
      File(path.join(packageRoot, out.path));

  /// Resolves the root directory of the package named [package] by looking it
  /// up in `.dart_tool/package_config.json` of the current directory.
  ///
  /// In a regular build, this is the current directory itself. In a pub
  /// workspace build, the current directory is the workspace root and the
  /// package is one of its members. Falls back to the current directory if
  /// the package cannot be found.
  Future<String> resolvePackageRoot(String package) async {
    final configFile = File(path.join('.dart_tool', 'package_config.json'));
    if (!await configFile.exists()) return Directory.current.path;
    try {
      final config = json.decode(await configFile.readAsString());
      final packages = (config as Map<String, dynamic>)['packages'] as List;
      for (final entry in packages.cast<Map<String, dynamic>>()) {
        if (entry['name'] != package) continue;
        // The root URI is either absolute or relative to the config file.
        final rootUri = configFile.absolute.uri
            .resolveUri(Uri.parse(entry['rootUri'] as String));
        return path.normalize(rootUri.toFilePath());
      }
    } catch (e) {
      log.warning('Could not resolve the root of package "$package" from '
          '${configFile.path}, using the current directory instead: $e');
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
