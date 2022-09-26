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
  static const defaultGrpcEnabled = false;
  static const defaultWellKnownTypesEnabled = false;

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
        grpcEnabled = options.config['grpc'] as bool? ?? defaultGrpcEnabled,
        wellKnownTypesEnabled = options.config['wellKnownTypesEnabled'] as bool? ?? defaultWellKnownTypesEnabled;

  final BuilderOptions options;

  final String protobufVersion;
  final String protocPluginVersion;
  final String rootDirectory;
  final List<String> protoPaths;
  final String outputDirectory;
  final bool grpcEnabled;
  final bool wellKnownTypesEnabled;

  @override
  Future<void> build(BuildStep buildStep) async {
    final protoc = await fetchProtoc(protobufVersion);
    final protocPlugin = await fetchProtocPlugin(protocPluginVersion);
    final wellKnownTypes = wellKnownTypesEnabled ? ' google/protobuf/any.proto google/protobuf/api.proto google/protobuf/descriptor.proto google/protobuf/duration.proto google/protobuf/empty.proto google/protobuf/field_mask.proto google/protobuf/source_context.proto google/protobuf/struct.proto google/protobuf/timestamp.proto google/protobuf/type.proto google/protobuf/wrappers.proto ' : '';

    final inputPath = path.normalize(buildStep.inputId.path);

    final pluginParameters = grpcEnabled ? 'grpc:' : '';

    // Read the input path to signal to the build graph that if the file changes
    // then it should be rebuilt.
    await buildStep.readAsString(buildStep.inputId);

    await Directory(outputDirectory).create(recursive: true);
    await ProcessExtensions.runSafely(
      protoc.path,
      [
        '--plugin=protoc-gen-dart=${protocPlugin.path}',
        '--dart_out=$pluginParameters${path.join('.', outputDirectory)}',
        ...protoPaths
            .map((protoPath) => '--proto_path=${path.join('.', protoPath)}'),
        path.join('.', inputPath),
        '$wellKnownTypes'
      ],
    );

    // Just as with the read, the build runner spies on what we write, so we
    // need to write each output file explicitly, even though they've already
    // been written by protoc. This will ensure that if an output file is
    // deleted, a future build will recreate it. This also checks that the files
    // we were expected to write were actually written, since this will fail if
    // an output file wasn't created by protoc.
    await Future.wait(buildStep.allowedOutputs.map((AssetId out) async {
      final file = File(out.path);
      // When there is no service definition in a .proto file, the respective
      // .pbgrpc.dart file is not generated. So, we will tolerate its absence.
      if (file.path.endsWith('.pbgrpc.dart') && !await file.exists()) {
        return;
      }

      await buildStep.writeAsBytes(out, file.readAsBytes());
    }));
  }

  @override
  Map<String, List<String>> get buildExtensions {
    return {
      path.join(rootDirectory, '{{}}.proto'): [
        path.join(outputDirectory, '{{}}.pb.dart'),
        path.join(outputDirectory, '{{}}.pbenum.dart'),
        path.join(outputDirectory, '{{}}.pbjson.dart'),
        if (!grpcEnabled) path.join(outputDirectory, '{{}}.pbserver.dart'),
        if (grpcEnabled) path.join(outputDirectory, '{{}}.pbgrpc.dart'),
      ],
    };
  }
}
