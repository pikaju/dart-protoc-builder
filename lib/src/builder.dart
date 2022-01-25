import 'dart:async';
import 'dart:io';

import 'package:build/build.dart';
import 'package:path/path.dart' as path;
import 'package:protoc_builder/src/protoc_plugin_download.dart';
import 'package:protoc_builder/src/utility.dart';
import 'package:yaml/yaml.dart';

import 'protoc_download.dart';

class ProtocBuilder implements Builder {
  static const defaultProtocVersion = '3.19.1';
  static const defaultProtocPluginVersion = '20.0.0';
  static const defaultRootDirectory = 'proto/';
  static const defaultProtoPaths = ['proto/'];
  static const defaultOutputDirectory = 'lib/src/proto/';
  static const defaultBuildDescriptor = false;

  ProtocBuilder(this.options)
      : protobufVersion = options.config['protobuf_version'] as String? ??
            defaultProtocVersion,
        protocPluginVersion =
            options.config['protoc_plugin_version'] as String? ??
                defaultProtocPluginVersion,
        rootDirectory = path.normalize(
            options.config['root_dir'] as String? ?? defaultRootDirectory),
        protoPaths = (options.config['proto_paths'] as YamlList?)
                ?.nodes
                .map((e) => e.value as String)
                .toList() ??
            defaultProtoPaths,
        outputDirectory = path.normalize(
            options.config['out_dir'] as String? ?? defaultOutputDirectory),
        buildDescriptor = options.config['build_descriptor'] as bool? ??
            defaultBuildDescriptor;

  final BuilderOptions options;

  final String protobufVersion;
  final String protocPluginVersion;
  final String rootDirectory;
  final List<String> protoPaths;
  final String outputDirectory;
  final bool buildDescriptor;

  @override
  Future<void> build(BuildStep buildStep) async {
    final protoc = await fetchProtoc(protobufVersion);
    final protocPlugin = await fetchProtocPlugin(protocPluginVersion);

    final inputPath = path.normalize(buildStep.inputId.path);

    // Read the input path to signal to the build graph that if the file changes
    // than it should be rebuilt.
    await buildStep.readAsString(buildStep.inputId);

    await Directory(outputDirectory).create(recursive: true);
    await ProcessExtensions.runSafely(
      protoc.path,
      [
        '--plugin=protoc-gen-dart=${protocPlugin.path}',
        '--dart_out=${path.join('.', outputDirectory)}',
        ...protoPaths
            .map((protoPath) => '--proto_path=${path.join('.', protoPath)}'),
        path.join('.', inputPath),
      ],
    );

    if (buildDescriptor) {
      String outputPath = buildStep.allowedOutputs
          .where((id) => id.path.endsWith('descriptor.pb'))
          .first
          .path;
      await ProcessExtensions.runSafely(
        protoc.path,
        [
          '--include_imports',
          '--include_source_info',
          '--descriptor_set_out=${path.join('.', outputPath)}',
          ...protoPaths
              .map((protoPath) => '--proto_path=${path.join('.', protoPath)}'),
          path.join('.', inputPath),
        ],
      );
    }

    // Just as with the read, the build runner spies on what we write, so we
    // need to write each output file explicitly, even though they've already
    // been written by protoc. This will ensure that if an output file is
    // deleted, a future build will recreate it. This also checks that the files
    // we were expected to write were actually written, since this will fail if
    // an output file wasn't created by protoc.
    await Future.wait(buildStep.allowedOutputs.map((AssetId out) async {
      await buildStep.writeAsBytes(out, File(out.path).readAsBytes());
    }));
  }

  @override
  Map<String, List<String>> get buildExtensions {
    return {
      path.join(rootDirectory, '{{}}.proto'): [
        path.join(outputDirectory, '{{}}.pb.dart'),
        path.join(outputDirectory, '{{}}.pbenum.dart'),
        path.join(outputDirectory, '{{}}.pbjson.dart'),
        path.join(outputDirectory, '{{}}.pbserver.dart'),
        if (buildDescriptor) path.join(outputDirectory, '{{}}.descriptor.pb'),
      ],
    };
  }
}
