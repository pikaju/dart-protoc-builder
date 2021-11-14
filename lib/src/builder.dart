import 'dart:async';
import 'dart:io';

import 'package:build/build.dart';
import 'package:path/path.dart' as path;
import 'package:protoc_builder/src/protoc_plugin_download.dart';
import 'package:yaml/yaml.dart';

import 'error.dart';
import 'protoc_download.dart';

class ProtocBuilder implements Builder {
  ProtocBuilder(this.options)
      : protobufVersion = options.config['protobuf_version'] as String?,
        rootDirectory = path.normalize(options.config['root_dir']),
        protoPaths = (options.config['proto_paths'] as YamlList)
            .nodes
            .map((e) => e.value as String)
            .toList(),
        outputDirectory = path.normalize(options.config['out_dir'] as String);

  final BuilderOptions options;

  final String? protobufVersion;
  final String rootDirectory;
  final List<String> protoPaths;
  final String outputDirectory;

  @override
  Future<void> build(BuildStep buildStep) async {
    final protoc = await downloadProtoc(protobufVersion!); //TODO
    final protocPluginDirectory = await downloadProtocPlugin('20.0.0');

    final inputPath = path.normalize(buildStep.inputId.path);
    if (!path.isWithin(rootDirectory, inputPath)) {
      throw ArgumentError(
          'Option root_dir must enclose all proto input files.');
    }

    final specificOutputDirectory = path.dirname(
      path.normalize(
        path.join(
          outputDirectory,
          path.relative(inputPath, from: rootDirectory),
        ),
      ),
    );

    await Directory(specificOutputDirectory).create(recursive: true);
    final result = await Process.run(
      protoc,
      [
        ...protoPaths
            .map((protoPath) => '--proto_path=${path.join('.', protoPath)}'),
        '--dart_out=${path.join('.', specificOutputDirectory)}',
        path.join('.', inputPath),
      ],
      environment: {
        'PATH': protocPluginDirectory,
      },
    );
    if (result.exitCode != 0) throw ProtocError(result);
  }

  @override
  Map<String, List<String>> get buildExtensions {
    return {
      path.join(rootDirectory, '{{}}.proto'): [
        path.join(outputDirectory, '{{}}.dart'),
        path.join(outputDirectory, '{{}}.enum.dart'),
      ],
    };
  }
}
